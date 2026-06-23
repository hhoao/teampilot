import '../../models/runtime_target.dart';

/// Derived flags for startup gating and transport selection. The single source
/// of truth is the home [RuntimeTarget]; `isSshMode` derives from its kind.
class ConnectionModeService {
  const ConnectionModeService({
    required RuntimeTarget Function() defaultTargetResolver,
    required bool Function() hasSshProfiles,
  }) : _defaultTargetResolver = defaultTargetResolver,
       _hasSshProfiles = hasSshProfiles;

  final RuntimeTarget Function() _defaultTargetResolver;
  final bool Function() _hasSshProfiles;

  bool get isSshMode => _defaultTargetResolver().kind == RuntimeKind.ssh;

  bool get isLocalMode => !isSshMode;

  /// SSH mode requires at least one saved profile before entering the app.
  bool get requiresSshProfileSetup => isSshMode && !_hasSshProfiles();
}
