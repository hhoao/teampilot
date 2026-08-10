import 'dart:async';

import '../../models/runtime_target.dart';
import '../../models/team_config.dart';
import 'package:logger/logger.dart';
import '../../utils/logging/logger.dart';
import '../cli/installer_types.dart';
import '../storage/work_target_canonicalizer.dart';
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
    final home = homeTarget();
    final resolved = WorkTargetCanonicalizer.resolve(
      memberTarget.id,
      home: home,
    );
    if (resolved.kind != RuntimeKind.ssh && resolved.kind != RuntimeKind.termux) {
      return false;
    }
    return resolved.id != home.id;
  }

  /// Background provision when a workspace tab opens or config changes.
  ///
  /// Attaches logging to a derived future so the shared [_inFlight] work future
  /// still completes with errors for [ensureReady] waiters.
  void schedule({
    required RuntimeTarget target,
    required String workspaceId,
    required CliTool cli,
    Iterable<String> trustedDirectories = const [],
  }) {
    final key = WorkspaceProvisionKey(
      targetId: target.id,
      workspaceId: workspaceId,
      cli: cli,
    );
    if (_ready.containsKey(key.cacheKey)) return;
    if (_inFlight.containsKey(key.cacheKey)) return;
    final work = _start(
      key,
      target: target,
      trustedDirectories: trustedDirectories,
    );
    unawaited(
      work.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _logProvisionFailed(key, error, stackTrace);
        },
      ),
    );
  }

  /// Blocks until workspace provision completes. Propagates errors to callers.
  Future<WorkspaceProvisionResult> ensureReady({
    required RuntimeTarget target,
    required String workspaceId,
    required CliTool cli,
    Iterable<String> trustedDirectories = const [],
    void Function(CliInstallProgress progress)? onProgress,
  }) async {
    final key = WorkspaceProvisionKey(
      targetId: target.id,
      workspaceId: workspaceId,
      cli: cli,
    );
    final cached = _ready[key.cacheKey];
    if (cached != null) {
      appLogger.d(
        '[workspace-provision] cache hit target=${key.targetId} '
        'workspace=${key.workspaceId} cli=${key.cli.value}',
      );
      return cached;
    }

    final inFlight = _inFlight[key.cacheKey];
    if (inFlight != null) {
      // Join in-flight work; progress callbacks only attach to the starter.
      return inFlight;
    }

    return _start(
      key,
      target: target,
      trustedDirectories: trustedDirectories,
      onProgress: onProgress,
    );
  }

  Future<WorkspaceProvisionResult> _start(
    WorkspaceProvisionKey key, {
    required RuntimeTarget target,
    Iterable<String> trustedDirectories = const [],
    void Function(CliInstallProgress progress)? onProgress,
  }) {
    final future = _runProvision(
      key,
      target: target,
      trustedDirectories: trustedDirectories,
      onProgress: onProgress,
    );
    _inFlight[key.cacheKey] = future;
    return future;
  }

  Future<WorkspaceProvisionResult> _runProvision(
    WorkspaceProvisionKey key, {
    required RuntimeTarget target,
    Iterable<String> trustedDirectories = const [],
    void Function(CliInstallProgress progress)? onProgress,
  }) async {
    // Heartbeat while provision hangs without throwing (SSH/SFTP stalls).
    final sw = Stopwatch()..start();
    final heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      appLogger.w(
        '[workspace-provision] still-running '
        'target=${key.targetId} workspace=${key.workspaceId} '
        'cli=${key.cli.value} elapsedMs=${sw.elapsedMilliseconds}',
      );
    });
    try {
      final result = await provisioner.provision(
        target: target,
        workspaceId: key.workspaceId,
        cli: key.cli,
        trustedDirectories: trustedDirectories,
        onProgress: onProgress,
      );
      _ready[key.cacheKey] = result;

      return result;
    } finally {
      heartbeat.cancel();
      _inFlight.remove(key.cacheKey);
    }
  }

  void _logProvisionFailed(
    WorkspaceProvisionKey key,
    Object error,
    StackTrace stackTrace,
  ) {
    appLogger.e(
      '[workspace-provision] failed '
      'target=${key.targetId} workspace=${key.workspaceId} '
      'cli=${key.cli.value}: $error',
      error: error,
      stackTrace: stackTrace,
    );
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
