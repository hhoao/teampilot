import 'dart:io';

import 'package:flutter/services.dart';

import '../../utils/logging/logger.dart';

/// Android-side bridge that keeps the app process alive while TeamPilot is
/// backgrounded. The existing session/attention connection then remains usable
/// and can deliver session-idle notifications.
///
/// This is intentionally not a push channel: if Android kills the app, the
/// foreground service is not restarted and no notification can be delivered.
class BackgroundAttentionService {
  BackgroundAttentionService({MethodChannel? channel, bool? isAndroid})
    : _channel = channel ?? const MethodChannel(channelName),
      _isAndroid = isAndroid;

  static const channelName = 'com.hhoa.teampilot/background';

  final MethodChannel _channel;

  /// Test override; defaults to [Platform.isAndroid].
  final bool? _isAndroid;

  bool? _lastEnabled;

  /// Mirrors the idle-notification preference to the native foreground-service
  /// switch. The native side starts the service on pause and stops it on resume,
  /// so the ongoing notification is only visible while the app is away.
  Future<void> setEnabled(bool enabled) async {
    final android = _isAndroid ?? Platform.isAndroid;
    if (!android) return;
    if (_lastEnabled == enabled) return;
    try {
      await _channel.invokeMethod<void>('setAttentionKeeperEnabled', {
        'enabled': enabled,
      });
      _lastEnabled = enabled;
      appLogger.i('[background-attention] keeper enabled=$enabled');
    } on MissingPluginException {
      appLogger.d('[background-attention] native keeper unavailable');
    } on PlatformException catch (error, stackTrace) {
      appLogger.w(
        '[background-attention] native keeper set enabled=$enabled failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
