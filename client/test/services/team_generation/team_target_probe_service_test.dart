import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/team_generation/models/team_target_probe.dart';
import 'package:teampilot/services/team_generation/team_target_probe_service.dart';

class _FakeRunner implements TeamTargetProbeRunner {
  final calls = <String>[];
  final Set<String> blocked = {};
  final Map<String, String> stdoutFor = {};

  @override
  Future<TeamTargetProbe> probe({
    required Workspace workspace,
    required String targetId,
    required Set<String> cliValues,
  }) async {
    calls.add(targetId);
    if (blocked.contains(targetId)) {
      await Completer<void>().future;
    }
    final stdout = stdoutFor[targetId] ?? '';
    return TeamTargetProbe(
      targetId: targetId,
      status: TeamTargetProbeStatus.available,
      folderIds: const [],
      cliProbes: [
        TeamTargetCliProbe(
          cliValue: 'claude',
          available: true,
          version: '1.0',
          diagnostic: stdout,
        ),
      ],
    );
  }
}

Workspace workspaceWithFolders(List<WorkspaceFolder> folders) => Workspace(
      workspaceId: 'ws',
      folders: folders,
      createdAt: 1,
      updatedAt: 1,
    );

void main() {
  test('probes each distinct live folder target once and keeps folder refs',
      () async {
    final runner = _FakeRunner();
    final service = TeamTargetProbeService(runner: runner);
    final workspace = workspaceWithFolders([
      const WorkspaceFolder(path: '/a', targetId: 'local'),
      const WorkspaceFolder(path: '/b', targetId: 'ssh-1'),
      const WorkspaceFolder(path: '/c', targetId: 'ssh-1'),
    ]);

    final result = await service.probe(
      workspace: workspace,
      cliValues: {'claude'},
    );

    expect(result.targets.map((target) => target.targetId).toList(),
        ['local', 'ssh-1']);
    expect(result.targets.last.folderIds, ['/b', '/c']);
    expect(runner.calls.where((id) => id == 'ssh-1'), hasLength(1));
  });

  test('timeout is a bounded unavailable result and output is truncated',
      () async {
    final runner = _FakeRunner();
    runner.blocked.add('ssh-1');
    runner.stdoutFor['local'] = 'x' * 20000;
    final service = TeamTargetProbeService(runner: runner);
    final workspace = workspaceWithFolders([
      const WorkspaceFolder(path: '/a', targetId: 'local'),
      const WorkspaceFolder(path: '/b', targetId: 'ssh-1'),
    ]);

    final result = await service.probe(
      workspace: workspace,
      cliValues: {'claude'},
    );

    expect(result.byTarget('ssh-1')!.status, TeamTargetProbeStatus.timeout);
    expect(
      result.byTarget('local')!.cliProbes.single.diagnostic.length,
      lessThanOrEqualTo(2048),
    );
  });

  test('one unreachable target stays structured and others still probe',
      () async {
    final runner = _FakeRunner();
    runner.blocked.add('ssh-2');
    // Blocked target never returns; use a short timeout service for it.
    final service = TeamTargetProbeService(
      runner: runner,
      timeout: const Duration(milliseconds: 50),
    );
    final workspace = workspaceWithFolders([
      const WorkspaceFolder(path: '/a', targetId: 'local'),
      const WorkspaceFolder(path: '/b', targetId: 'ssh-2'),
    ]);

    final result = await service.probe(
      workspace: workspace,
      cliValues: {'claude'},
    );

    expect(result.byTarget('ssh-2')!.status, TeamTargetProbeStatus.timeout);
    expect(result.byTarget('local')!.status, TeamTargetProbeStatus.available);
  });
}
