import 'hlc.dart';

/// Process-wide device identity for shared-state stamps.
///
/// The real id is loaded from the device plane at boot and installed with
/// [configure]. Tests and lightweight harnesses that do not boot the full app
/// fall back to a stable placeholder; callers that need isolated replicas in
/// one process pass an explicit `deviceId`/clock to the store instead.
abstract final class SharedStateIdentity {
  static String _deviceId = 'device-local';
  static HlcClock _clock = HlcClock(nodeId: _deviceId);

  static String get deviceId => _deviceId;

  static HlcClock get clock => _clock;

  static void configure({required String deviceId, HlcClock? clock}) {
    final trimmed = deviceId.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId');
    }
    _deviceId = trimmed;
    _clock = clock ?? HlcClock(nodeId: trimmed);
  }

  /// The shared clock when [deviceId] is the current device, otherwise a
  /// per-call clock for a test replica.
  static HlcClock clockFor(String? deviceId) {
    final trimmed = deviceId?.trim() ?? '';
    return trimmed.isEmpty || trimmed == _deviceId
        ? _clock
        : HlcClock(nodeId: trimmed);
  }
}
