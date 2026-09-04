import 'dart:async';

import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import 'models/team_target_probe.dart';

/// Read-only probing of live workspace folder targets.
///
/// - Targets derive only from live [Workspace.folders]; the canonical home
///   target is `local`; stale target ids become typed unavailable facts.
/// - Distinct targets probe once, concurrently bounded at four, each with a
///   12-second timeout.
/// - Output fields are redacted and bounded; runners never mutate anything.
final class TeamTargetProbeService {
  TeamTargetProbeService({
    required TeamTargetProbeRunner runner,
    int concurrency = 4,
    Duration timeout = const Duration(seconds: 12),
    DateTime Function()? clock,
  }) : _runner = runner,
       _concurrency = concurrency < 1 ? 1 : concurrency,
       _timeout = timeout,
       _clock = clock ?? DateTime.now;

  final TeamTargetProbeRunner _runner;
  final int _concurrency;
  final Duration _timeout;
  final DateTime Function() _clock;

  Future<TeamTargetProbeSnapshot> probe({
    required Workspace workspace,
    required Set<String> cliValues,
  }) async {
    // Canonical target derivation: folder order defines folder membership.
    final targets = <String, List<String>>{};
    for (final folder in workspace.folders) {
      final id = _canonicalTargetId(folder);
      targets.putIfAbsent(id, () => []).add(_folderId(workspace, folder));
    }
    final capturedAt = _clock().millisecondsSinceEpoch;
    final targetIds = targets.keys.toList();

    final results = <String, TeamTargetProbe>{};
    var index = 0;
    Future<void> worker() async {
      while (index < targetIds.length) {
        final current = targetIds[index++];
        results[current] = await _probeOne(
          workspace: workspace,
          targetId: current,
          folderIds: targets[current] ?? const [],
          cliValues: cliValues,
          capturedAt: capturedAt,
        );
      }
    }

    final workers = List.generate(
      targetIds.length < _concurrency ? targetIds.length : _concurrency,
      (_) => worker(),
    );
    await Future.wait(workers);

    return TeamTargetProbeSnapshot(
      capturedAt: capturedAt,
      targets: [
        for (final id in targetIds) results[id]!,
      ],
    );
  }

  Future<TeamTargetProbe> _probeOne({
    required Workspace workspace,
    required String targetId,
    required List<String> folderIds,
    required Set<String> cliValues,
    required int capturedAt,
  }) async {
    try {
      final probed = await _runner
          .probe(
            workspace: workspace,
            targetId: targetId,
            cliValues: cliValues,
          )
          .timeout(_timeout);
      // The runner does not know folder membership; stamp it here so folder
      // refs survive even when a runner returns a bare probe. Diagnostics are
      // re-bounded here so runner output can never exceed the cap.
      return TeamTargetProbe(
        targetId: probed.targetId.isEmpty ? targetId : probed.targetId,
        status: probed.status,
        folderIds: folderIds,
        cliProbes: [
          for (final probe in probed.cliProbes)
            TeamTargetCliProbe.bounded(
              cliValue: probe.cliValue,
              available: probe.available,
              version: probe.version,
              executableBasename: probe.executableBasename,
              diagnostic: probe.diagnostic,
            ),
        ],
        transportKind: probed.transportKind,
        os: probed.os,
        arch: probed.arch,
        cpuCount: probed.cpuCount,
        capturedAt: capturedAt,
      );
    } on TimeoutException {
      return TeamTargetProbe(
        targetId: targetId,
        status: TeamTargetProbeStatus.timeout,
        folderIds: folderIds,
        cliProbes: const [],
        capturedAt: capturedAt,
      );
    } on Object catch (e) {
      return TeamTargetProbe(
        targetId: targetId,
        status: TeamTargetProbeStatus.unavailable,
        folderIds: folderIds,
        cliProbes: [
          TeamTargetCliProbe.bounded(
            cliValue: '*',
            available: false,
            diagnostic: e.toString(),
          ),
        ],
        capturedAt: capturedAt,
      );
    }
  }

  String _canonicalTargetId(WorkspaceFolder folder) {
    final raw = folder.targetId.trim();
    if (raw.isEmpty || raw == WorkspaceFolder.localTargetId) {
      return WorkspaceFolder.localTargetId;
    }
    return raw;
  }

  String _folderId(Workspace workspace, WorkspaceFolder folder) =>
      folder.path.trim();
}
