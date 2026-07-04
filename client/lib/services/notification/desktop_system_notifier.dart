import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:window_manager/window_manager.dart';

/// OS-level notifications via [flutter_local_notifications].
class DesktopSystemNotifier {
  DesktopSystemNotifier({
    FlutterLocalNotificationsPlugin? plugin,
    Future<bool> Function()? isAppFocused,
    Future<void> Function(String appName)? setup,
    Future<void> Function({required String title, required String body})? show,
  })  : _plugin = plugin,
        _isAppFocused = isAppFocused ?? _defaultIsAppFocused,
        _setup = setup,
        _show = show;

  static final DesktopSystemNotifier instance = DesktopSystemNotifier();

  static bool _initialized = false;
  static FlutterLocalNotificationsPlugin? _sharedPlugin;

  static const _androidChannelId = 'session_idle';
  static const _androidChannelName = 'Session idle';
  static const _windowsAppUserModelId = 'com.hhoa.teampilot';
  static const _windowsGuid = '7c4f8a2e-1b9d-4e6a-9f3c-2d8e5a1b6c0d';

  final FlutterLocalNotificationsPlugin? _plugin;
  final Future<bool> Function() _isAppFocused;
  final Future<void> Function(String appName)? _setup;
  final Future<void> Function({required String title, required String body})?
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

  Future<bool> isAppFocused() => _isAppFocused();

  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    final show = _show;
    if (show != null) {
      await show(title: title, body: body);
      return;
    }
    await _defaultShow(title: title, body: body);
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
    await plugin.initialize(
      settings: InitializationSettings(
        android: Platform.isAndroid
            ? const AndroidInitializationSettings('@mipmap/ic_launcher')
            : null,
        macOS: Platform.isMacOS ? const DarwinInitializationSettings() : null,
        linux: Platform.isLinux
            ? const LinuxInitializationSettings(defaultActionName: 'Open')
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

    if (Platform.isAndroid) {
      await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (Platform.isMacOS) {
      await plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: false, sound: true);
    }
  }

  Future<void> _defaultShow({
    required String title,
    required String body,
  }) async {
    await _ensureReady();

    final id = _nextNotificationId++;
    final details = NotificationDetails(
      android: Platform.isAndroid
          ? const AndroidNotificationDetails(
              _androidChannelId,
              _androidChannelName,
              channelDescription: 'Notifies when an agent session becomes idle',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            )
          : null,
      macOS: Platform.isMacOS ? const DarwinNotificationDetails() : null,
      linux: Platform.isLinux ? const LinuxNotificationDetails() : null,
      windows: Platform.isWindows ? const WindowsNotificationDetails() : null,
    );

    await _effectivePlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }
}
