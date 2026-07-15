import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/workspace/target_liveness.dart';

class _FixedLiveness implements TargetLiveness {
  _FixedLiveness(this._alive);

  final Set<String> _alive;

  @override
  Future<bool> isAlive(String targetId) async => _alive.contains(targetId);
}

void main() {
  test('remapWorkspaceTarget rewrites folders, pins, and sessions', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_remap_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace([
      const WorkspaceFolder(path: '/local'),
      const WorkspaceFolder(path: '/remote', targetId: 'ssh:old'),
    ]);
    await repo.updateWorkspaceMemberPlacement(
      ws.workspaceId,
      'team-a',
      targets: const {'team-lead': 'local', 'dev': 'ssh:old'},
    );
    final beforeWs = (await repo.loadWorkspaces()).single;
    expect(beforeWs.memberPlacementInitializedByTeam['team-a'], isTrue);

    final session = await repo.createSession(
      ws.workspaceId,
      sessionTeam: 'team-a',
      rosterMembers: const [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'dev', name: 'Dev'),
      ],
    );
    expect(
      session.folders.any((f) => f.targetId == 'ssh:old'),
      isTrue,
    );
    expect(session.memberTargets['dev'], 'ssh:old');

    await repo.remapWorkspaceTarget(
      ws.workspaceId,
      fromTargetId: 'ssh:old',
      toTargetId: 'ssh:new',
      liveness: _FixedLiveness({'ssh:new', 'local', 'ssh:old'}),
    );

    final reloadedWs = (await repo.loadWorkspaces()).single;
    expect(
      reloadedWs.folders.map((f) => f.targetId),
      ['local', 'ssh:new'],
    );
    expect(reloadedWs.memberTargetsByTeam['team-a']?['dev'], 'ssh:new');
    expect(reloadedWs.memberPlacementInitializedByTeam['team-a'], isTrue);

    final reloadedSessions = await repo.loadSessionsForWorkspace(ws.workspaceId);
    expect(reloadedSessions, hasLength(1));
    final reloadedSession = reloadedSessions.single;
    expect(
      reloadedSession.folders.any((f) => f.targetId == 'ssh:new'),
      isTrue,
    );
    expect(reloadedSession.folders.any((f) => f.targetId == 'ssh:old'), isFalse);
    expect(reloadedSession.memberTargets['dev'], 'ssh:new');
  });

  test('remapWorkspaceTarget throws when from target is unused', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_repo_remap_unused_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace([
      const WorkspaceFolder(path: '/local'),
    ]);

    expect(
      () => repo.remapWorkspaceTarget(
        ws.workspaceId,
        fromTargetId: 'ssh:gone',
        toTargetId: 'ssh:new',
        liveness: _FixedLiveness({'ssh:new', 'local'}),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'Nothing to remap for target "ssh:gone"',
        ),
      ),
    );
  });

  test(
    'remapWorkspaceTarget rejects dead destination before writing',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_repo_remap_dead_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SessionRepository(rootDir: tmp.path);

      final ws = await repo.createWorkspace([
        const WorkspaceFolder(path: '/local'),
        const WorkspaceFolder(path: '/remote', targetId: 'ssh:old'),
      ]);
      await repo.updateWorkspaceMemberPlacement(
        ws.workspaceId,
        'team-a',
        targets: const {'team-lead': 'ssh:old'},
      );

      expect(
        () => repo.remapWorkspaceTarget(
          ws.workspaceId,
          fromTargetId: 'ssh:old',
          toTargetId: 'ssh:dead',
          liveness: _FixedLiveness({'local', 'ssh:old'}),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Destination target "ssh:dead" is not available',
          ),
        ),
      );

      final unchanged = (await repo.loadWorkspaces()).single;
      expect(
        unchanged.folders.map((f) => f.targetId),
        ['local', 'ssh:old'],
      );
      expect(unchanged.memberTargetsByTeam['team-a']?['team-lead'], 'ssh:old');
    },
  );
}
