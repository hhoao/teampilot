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

  bool get isTermuxMode =>
      _defaultTargetResolver().kind == RuntimeKind.termux;

  bool get hasBoundAndroidWorkHome => isSshMode || isTermuxMode;

  bool get isRemoteWorkPlane => isSshMode || isTermuxMode;

  bool get isLocalMode =>
      _defaultTargetResolver().kind == RuntimeKind.local;

  /// SSH mode requires at least one saved profile before entering the app.
  bool get requiresSshProfileSetup => isSshMode && !_hasSshProfiles();
}
