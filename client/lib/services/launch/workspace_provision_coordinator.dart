import 'dart:async';

import '../../models/personal_profile.dart';
import '../../models/runtime_target.dart';
import '../../models/team_config.dart';
import '../../utils/logger.dart';
import 'launch_artifacts.dart';
import 'workspace_provisioner.dart';

/// Tracks workspace-level provision jobs per (target, workspace, cli).
class WorkspaceProvisionCoordinator {
  WorkspaceProvisionCoordinator({
    required this.provisioner,
    required this.homeTarget,
  });

  final WorkspaceProvisioner provisioner;
  final RuntimeTarget Function() homeTarget;

  final Map<String, Future<WorkspaceProvisionResult>> _inFlight = {};
  final Map<String, WorkspaceProvisionResult> _ready = {};

  bool isOffHome(RuntimeTarget memberTarget) {
    if (memberTarget.kind != RuntimeKind.ssh) return false;
    return memberTarget.id != homeTarget().id;
  }

  /// Background provision when a workspace tab opens or config changes.
  void schedule({
    required RuntimeTarget target,
    required String workspaceId,
    required CliTool cli,
    required PersonalProfile? personal,
    Iterable<String> trustedDirectories = const [],
  }) {
    final key = WorkspaceProvisionKey(
      targetId: target.id,
      workspaceId: workspaceId,
      cli: cli,
    );
    if (_ready.containsKey(key.cacheKey)) return;
    if (_inFlight.containsKey(key.cacheKey)) return;
    unawaited(() async {
      try {
        await _start(
          key,
          target: target,
          personal: personal,
          trustedDirectories: trustedDirectories,
        );
      } on Object catch (error, stackTrace) {
        appLogger.e(
          '[workspace-provision] background failed '
          'target=${key.targetId} workspace=${key.workspaceId} '
          'cli=${key.cli.value}: $error',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }());
  }

  /// Blocks until workspace provision completes. Fails fast on error.
  Future<WorkspaceProvisionResult> ensureReady({
    required RuntimeTarget target,
    required String workspaceId,
    required CliTool cli,
    PersonalProfile? personal,
    Iterable<String> trustedDirectories = const [],
  }) async {
    final key = WorkspaceProvisionKey(
      targetId: target.id,
      workspaceId: workspaceId,
      cli: cli,
    );
    final cached = _ready[key.cacheKey];
    if (cached != null) return cached;

    final inFlight = _inFlight[key.cacheKey];
    if (inFlight != null) return inFlight;

    return _start(
      key,
      target: target,
      personal: personal,
      trustedDirectories: trustedDirectories,
    );
  }

  Future<WorkspaceProvisionResult> _start(
    WorkspaceProvisionKey key, {
    required RuntimeTarget target,
    required PersonalProfile? personal,
    Iterable<String> trustedDirectories = const [],
  }) {
    final future = provisioner
        .provision(
          target: target,
          workspaceId: key.workspaceId,
          cli: key.cli,
          personal: personal,
          trustedDirectories: trustedDirectories,
        )
        .then((result) {
          _ready[key.cacheKey] = result;
          return result;
        })
        .whenComplete(() => _inFlight.remove(key.cacheKey));
    _inFlight[key.cacheKey] = future;
    return future;
  }

  void invalidate({
    required String targetId,
    required String workspaceId,
    CliTool? cli,
  }) {
    final prefix = cli == null
        ? '$targetId|$workspaceId|'
        : WorkspaceProvisionKey(
            targetId: targetId,
            workspaceId: workspaceId,
            cli: cli,
          ).cacheKey;
    _ready.removeWhere((k, _) => k.startsWith(prefix) || k == prefix);
    _inFlight.removeWhere((k, _) => k.startsWith(prefix) || k == prefix);
    appLogger.d(
      '[workspace-provision] invalidated target=$targetId workspace=$workspaceId',
    );
  }

  void invalidateWorkspace(WorkspaceProvisionKey key) {
    invalidate(
      targetId: key.targetId,
      workspaceId: key.workspaceId,
      cli: key.cli,
    );
  }
}
