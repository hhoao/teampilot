import '../models/connection_mode.dart';

/// Resolves the active [ConnectionMode] and derived flags for startup gating,
/// transport selection, and remote CLI discovery.
class ConnectionModeService {
  const ConnectionModeService({
    required ConnectionMode Function() readPreferredMode,
    required bool Function() hasSshProfiles,
  })  : _readPreferredMode = readPreferredMode,
        _hasSshProfiles = hasSshProfiles;

  final ConnectionMode Function() _readPreferredMode;
  final bool Function() _hasSshProfiles;

  ConnectionMode get preferredMode => _readPreferredMode();

  ConnectionMode get effectiveMode => preferredMode;

  bool get isSshMode => effectiveMode == ConnectionMode.ssh;

  bool get isLocalMode => effectiveMode == ConnectionMode.localPty;

  /// SSH mode requires at least one saved profile before entering the app.
  bool get requiresSshProfileSetup => isSshMode && !_hasSshProfiles();
}
