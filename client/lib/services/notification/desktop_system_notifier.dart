import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../utils/logger.dart';

/// OS-level notifications via [flutter_local_notifications].
class DesktopSystemNotifier {
  DesktopSystemNotifier({
    FlutterLocalNotificationsPlugin? plugin,
    Future<void> Function(String appName)? setup,
    Future<void> Function({
      required String title,
      required String body,
      String? subtitle,
    })?
    show,
  }) : _plugin = plugin,
       _setup = setup,
       _show = show;

  static final DesktopSystemNotifier instance = DesktopSystemNotifier();

  static bool _initialized = false;
  static FlutterLocalNotificationsPlugin? _sharedPlugin;

  static const _androidChannelId = 'session_idle';
  static const _androidChannelName = 'Agent updates';
  static const _windowsAppUserModelId = 'com.hhoa.teampilot';
  static const _windowsGuid = '7c4f8a2e-1b9d-4e6a-9f3c-2d8e5a1b6c0d';
  static const _linuxAppIconPath = 'assets/icons/icon_bg.png';

  final FlutterLocalNotificationsPlugin? _plugin;
  final Future<void> Function(String appName)? _setup;
  final Future<void> Function({
    required String title,
    required String body,
    String? subtitle,
  })?
  _show;

  int _nextNotificationId = 1;

  FlutterLocalNotificationsPlugin get _effectivePlugin =>
      _plugin ?? _sharedPlugin ?? FlutterLocalNotificationsPlugin();

  static Future<void> ensureInitialized({String appName = 'TeamPilot'}) async {
    if (kIsWeb || _initialized) return;
    _sharedPlugin ??= FlutterLocalNotificationsPlugin();
    await _initializePlugin(_sharedPlugin!, appName);
    _initialized = true;
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? subtitle,
  }) async {
    final show = _show;
    if (show != null) {
      await show(title: title, body: body, subtitle: subtitle);
      return;
    }
    await _defaultShow(title: title, body: body, subtitle: subtitle);
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
        macOS: Platform.isMacOS ? const DarwinInitializationSettings() : null,
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
    );
    if (ok != true) {
      appLogger.w('[system-notifier] flutter_local_notifications init failed');
    }

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

  Future<void> _defaultShow({
    required String title,
    required String body,
    String? subtitle,
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
    );
    appLogger.d('[system-notifier] showed id=$id title=$title');
  }
}
