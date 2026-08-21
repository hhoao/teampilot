import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:window_manager/window_manager.dart';

import '../../utils/logging/logger.dart';

typedef NotificationTapHandler = void Function(String? payload);

/// OS-level notifications via [flutter_local_notifications].
class DesktopSystemNotifier {
  DesktopSystemNotifier({
    FlutterLocalNotificationsPlugin? plugin,
    Future<bool> Function()? isAppFocused,
    Future<void> Function(String appName)? setup,
    Future<void> Function({
      required String title,
      required String body,
      String? subtitle,
      String? payload,
    })?
    show,
  }) : _plugin = plugin,
       _isAppFocused = isAppFocused ?? _defaultIsAppFocused,
       _setup = setup,
       _show = show;

  static final DesktopSystemNotifier instance = DesktopSystemNotifier();

  static bool _initialized = false;
  static bool _permissionsRequested = false;
  static FlutterLocalNotificationsPlugin? _sharedPlugin;
  static NotificationTapHandler? _onNotificationTap;

  /// macOS/iOS: defer permission prompts out of [initialize] so the dialog is
  /// not shown while the main window is still hidden behind the boot splash.
  static const _darwinInitSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestSoundPermission: false,
    requestBadgePermission: false,
  );

  static const _androidChannelId = 'session_idle';
  static const _androidChannelName = 'Agent updates';
  static const _windowsAppUserModelId = 'com.hhoa.teampilot';
  static const _windowsGuid = '7c4f8a2e-1b9d-4e6a-9f3c-2d8e5a1b6c0d';
  static const _linuxAppIconPath = 'assets/icons/icon_bg.png';

  final FlutterLocalNotificationsPlugin? _plugin;
  final Future<bool> Function() _isAppFocused;
  final Future<void> Function(String appName)? _setup;
  final Future<void> Function({
    required String title,
    required String body,
    String? subtitle,
    String? payload,
  })?
  _show;

  int _nextNotificationId = 1;

  FlutterLocalNotificationsPlugin get _effectivePlugin =>
      _plugin ?? _sharedPlugin ?? FlutterLocalNotificationsPlugin();

  /// Registers [onNotificationTap] for subsequent OS notification clicks.
  ///
  /// Hot-start only: does not consume [getNotificationAppLaunchDetails].
  static Future<void> ensureInitialized({
    String appName = 'TeamPilot',
    NotificationTapHandler? onNotificationTap,
  }) async {
    if (onNotificationTap != null) {
      _onNotificationTap = onNotificationTap;
    }
    if (kIsWeb || _initialized) return;
    _sharedPlugin ??= FlutterLocalNotificationsPlugin();
    await _initializePlugin(_sharedPlugin!, appName);
    _initialized = true;
  }

  /// Requests OS notification permission once the app window is visible.
  ///
  /// Safe to call multiple times; no-ops after the first successful request.
  static Future<void> requestPlatformPermissions() async {
    if (kIsWeb || _permissionsRequested || !_initialized) return;
    final plugin = _sharedPlugin;
    if (plugin == null) return;
    _permissionsRequested = true;
    await _requestPlatformPermissions(plugin);
  }

  @visibleForTesting
  static void debugResetForTest() {
    _initialized = false;
    _permissionsRequested = false;
    _sharedPlugin = null;
    _onNotificationTap = null;
  }

  @visibleForTesting
  static void debugDispatchTap(String? payload) {
    _onNotificationTap?.call(payload);
  }

  Future<bool> isAppFocused() => _isAppFocused();

  Future<void> showNotification({
    required String title,
    required String body,
    String? subtitle,
    String? payload,
  }) async {
    final show = _show;
    if (show != null) {
      await show(
        title: title,
        body: body,
        subtitle: subtitle,
        payload: payload,
      );
      return;
    }
    await _defaultShow(
      title: title,
      body: body,
      subtitle: subtitle,
      payload: payload,
    );
  }

  Future<void> _ensureReady() async {
    final setup = _setup;
    if (setup != null) {
      await setup('TeamPilot');
      return;
    }
    if (!_initialized) {
      await ensureInitialized();
    }
    await requestPlatformPermissions();
  }

  static Future<bool> _defaultIsAppFocused() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    }
    return windowManager.isFocused();
  }

  static Future<void> _initializePlugin(
    FlutterLocalNotificationsPlugin plugin,
    String appName,
  ) async {
    final ok = await plugin.initialize(
      settings: InitializationSettings(
        android: Platform.isAndroid
            ? const AndroidInitializationSettings('@mipmap/ic_launcher')
            : null,
        macOS: Platform.isMacOS ? _darwinInitSettings : null,
        linux: Platform.isLinux
            ? LinuxInitializationSettings(
                defaultActionName: 'Open',
                defaultIcon: AssetsLinuxIcon(_linuxAppIconPath),
              )
            : null,
        windows: Platform.isWindows
            ? WindowsInitializationSettings(
                appName: appName,
                appUserModelId: _windowsAppUserModelId,
                guid: _windowsGuid,
              )
            : null,
      ),
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
    );
    // On Darwin, initialize() returns permission grant status when permissions
    // are requested at init time. We defer prompts to
    // [requestPlatformPermissions] instead.
    appLogger.d(
      '[system-notifier] flutter_local_notifications ready ok=$ok',
    );
  }

  static Future<void> _requestPlatformPermissions(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    if (Platform.isAndroid) {
      final granted = await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      appLogger.d('[system-notifier] Android notification permission=$granted');
    } else if (Platform.isMacOS) {
      final granted = await plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: false, sound: true);
      appLogger.d('[system-notifier] macOS notification permission=$granted');
    } else if (Platform.isLinux) {
      final linux = plugin
          .resolvePlatformSpecificImplementation<
            LinuxFlutterLocalNotificationsPlugin
          >();
      final caps = await linux?.getCapabilities();
      appLogger.d('[system-notifier] Linux notification capabilities=$caps');
    }
  }

  static void _onDidReceiveNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    appLogger.d('[system-notifier] notification tap payload=$payload');
    _onNotificationTap?.call(payload);
  }

  Future<void> _defaultShow({
    required String title,
    required String body,
    String? subtitle,
    String? payload,
  }) async {
    await _ensureReady();

    final id = _nextNotificationId++;
    final badge = subtitle?.trim();
    final details = NotificationDetails(
      android: Platform.isAndroid
          ? AndroidNotificationDetails(
              _androidChannelId,
              _androidChannelName,
              channelDescription:
                  'Alerts when an agent session finishes and waits for you',
              importance: Importance.high,
              priority: Priority.high,
              ticker: title,
              styleInformation: BigTextStyleInformation(
                body,
                contentTitle: title,
                summaryText: badge?.isNotEmpty == true ? badge : 'TeamPilot',
              ),
            )
          : null,
      macOS: Platform.isMacOS
          ? DarwinNotificationDetails(
              subtitle: badge?.isNotEmpty == true ? badge : 'TeamPilot',
              presentAlert: true,
              presentSound: true,
            )
          : null,
      linux: Platform.isLinux
          ? LinuxNotificationDetails(
              urgency: LinuxNotificationUrgency.normal,
              category: LinuxNotificationCategory.im,
              icon: AssetsLinuxIcon(_linuxAppIconPath),
            )
          : null,
      windows: Platform.isWindows
          ? WindowsNotificationDetails(
              subtitle: badge?.isNotEmpty == true ? badge : null,
              duration: WindowsNotificationDuration.short,
            )
          : null,
    );

    await _effectivePlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
    appLogger.d('[system-notifier] showed id=$id title=$title payload=$payload');
  }
}
