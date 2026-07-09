import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';

void main() {
  test(
    'createSession allocates one binding per instance via replicas',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_rep_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/replicas'),
      ]);
      final workspaceId = workspace.workspaceId;

      final session = await repo.createSession(
        workspaceId,
        sessionTeam: 'team-1',
        rosterMembers: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
        ],
      );
      expect(session.members.map((b) => b.rosterMemberId), [
        'team-lead',
        'builder-0',
        'builder-1',
      ]);
      expect(session.members.map((b) => b.typeId), [
        'team-lead',
        'builder',
        'builder',
      ]);
      expect(session.members.map((b) => b.taskId).toSet().length, 3);
    },
  );

  test(
    'createSession omits mixed instances without targets when initialized',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_omit_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SessionRepository(rootDir: tmp.path);

      final ws = await repo.createWorkspace([
        const WorkspaceFolder(path: '/local'),
        const WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ]);
      await repo.updateWorkspaceMemberPlacement(
        ws.workspaceId,
        'team-a',
        targets: const {'team-lead': 'local'},
      );

      final session = await repo.createSession(
        ws.workspaceId,
        sessionTeam: 'team-a',
        rosterMembers: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'Dev', replicas: 2),
        ],
      );

      expect(session.members.map((b) => b.rosterMemberId), ['team-lead']);
      expect(session.memberTargets.keys, {'team-lead'});
    },
  );

  test(
    'createSession implicitly pins missing targets on single-host',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_pin_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SessionRepository(rootDir: tmp.path);

      final ws = await repo.createWorkspace([
        const WorkspaceFolder(path: '/local'),
      ]);
      await repo.updateWorkspaceMemberTargets(
        ws.workspaceId,
        'team-1',
        targets: const {'team-lead': 'local'},
      );

      final session = await repo.createSession(
        ws.workspaceId,
        sessionTeam: 'team-1',
        rosterMembers: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'Dev', replicas: 2),
        ],
      );

      expect(session.memberTargets, {
        'team-lead': 'local',
        'dev-0': 'local',
        'dev-1': 'local',
      });
      expect(session.members.map((b) => b.rosterMemberId).toSet(), {
        'team-lead',
        'dev-0',
        'dev-1',
      });
    },
  );

  test(
    'createSession empty single-host targets persists default pins',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_def_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SessionRepository(rootDir: tmp.path);

      final ws = await repo.createWorkspace([
        const WorkspaceFolder(path: '/local'),
      ]);

      final session = await repo.createSession(
        ws.workspaceId,
        sessionTeam: 'team-1',
        rosterMembers: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'Dev', replicas: 2),
        ],
      );

      expect(session.memberTargets, {
        'team-lead': 'local',
        'dev-0': 'local',
        'dev-1': 'local',
      });

      final reloaded = (await repo.loadWorkspaces()).single;
      expect(reloaded.memberTargetsByTeam['team-1'], {
        'team-lead': 'local',
        'dev-0': 'local',
        'dev-1': 'local',
      });
    },
  );

  test('createSession throws when mixed not initialized', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_uninit_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);

    final ws = await repo.createWorkspace([
      const WorkspaceFolder(path: '/local'),
      const WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
    ]);

    expect(
      () => repo.createSession(
        ws.workspaceId,
        sessionTeam: 'team-a',
        rosterMembers: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        ],
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'mixed_workspace_member_placement_uninitialized',
        ),
      ),
    );
  });
}
