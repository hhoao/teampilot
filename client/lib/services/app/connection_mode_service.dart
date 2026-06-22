import '../../models/connection_mode.dart';
import '../../models/runtime_target.dart';

/// Resolves the active [ConnectionMode] and derived flags for startup gating,
/// transport selection, and remote CLI discovery.
///
/// P0: the single source of truth is the default [RuntimeTarget]; `isSshMode`
/// derives from its kind (no separate connection-mode knob).
class ConnectionModeService {
  const ConnectionModeService({
    required RuntimeTarget Function() defaultTargetResolver,
    required bool Function() hasSshProfiles,
  }) : _defaultTargetResolver = defaultTargetResolver,
       _hasSshProfiles = hasSshProfiles;

  final RuntimeTarget Function() _defaultTargetResolver;
  final bool Function() _hasSshProfiles;

  ConnectionMode get effectiveMode =>
      isSshMode ? ConnectionMode.ssh : ConnectionMode.localPty;

  ConnectionMode get preferredMode => effectiveMode;

  bool get isSshMode => _defaultTargetResolver().kind == RuntimeKind.ssh;

  bool get isLocalMode => !isSshMode;

  /// SSH mode requires at least one saved profile before entering the app.
  bool get requiresSshProfileSetup => isSshMode && !_hasSshProfiles();
}
