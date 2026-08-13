import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
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

      final session = (await repo.createSession(
        workspaceId,
        sessionTeam: 'team-1',
        rosterMembers: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
        ],

        memberClis: const {
          'team-lead': CliTool.claude,
          'builder': CliTool.claude,
        },
      )).session;
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
    'createSession heals stale replicas from remembered instance pins',
    () async {
      final tmp = await Directory.systemTemp.createTemp(
        'fs_session_repo_heal_',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SessionRepository(rootDir: tmp.path);

      final ws = await repo.createWorkspace([
        const WorkspaceFolder(path: '/local'),
        const WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ]);
      await repo.updateWorkspaceMemberPlacement(
        ws.workspaceId,
        'team-a',
        targets: const {
          'team-lead': 'local',
          'builder-0': 'local',
          'builder-1': 'ssh:p1',
        },
      );

      // Profile still says replicas:1 (bug: placement wrote targets only).
      final session = (await repo.createSession(
        ws.workspaceId,
        sessionTeam: 'team-a',
        rosterMembers: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 1),
        ],

        memberClis: const {
          'team-lead': CliTool.claude,
          'builder': CliTool.claude,
        },
      )).session;

      expect(session.members.map((b) => b.rosterMemberId).toList(), [
        'team-lead',
        'builder-0',
        'builder-1',
      ]);
      expect(session.memberTargets['builder-0'], 'local');
      expect(session.memberTargets['builder-1'], 'ssh:p1');
    },
  );

  test(
    'healed session still yields builder pods when in-memory team replicas lag',
    () async {
      // Regression: createSession wrote builder-0/1 from workspace pins, but
      // LaunchProfileCubit still held replicas=1. Bus/UI used to expand+filter
      // and drop both builders (members=3, no builder connect).
      final tmp = await Directory.systemTemp.createTemp(
        'fs_session_repo_roster_',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SessionRepository(rootDir: tmp.path);

      final ws = await repo.createWorkspace([
        const WorkspaceFolder(path: '/local'),
        const WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ]);
      await repo.updateWorkspaceMemberPlacement(
        ws.workspaceId,
        'team-a',
        targets: const {
          'team-lead': 'local',
          'architect': 'local',
          'builder-0': 'local',
          'builder-1': 'ssh:p1',
          'reviewer': 'local',
        },
      );

      const staleTeam = TeamProfile(
        id: 'team-a',
        name: 'Team A',
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
        members: [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'architect', name: 'Architect'),
          TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 1),
          TeamMemberConfig(id: 'reviewer', name: 'Reviewer'),
        ],
      );

      final session = (await repo.createSession(
        ws.workspaceId,
        sessionTeam: 'team-a',
        rosterMembers: staleTeam.members,

        memberClis: {for (final m in staleTeam.members) m.id: CliTool.claude},
      )).session;

      expect(session.members.map((b) => b.rosterMemberId).toList(), [
        'team-lead',
        'architect',
        'builder-0',
        'builder-1',
        'reviewer',
      ]);
      expect(
        sessionRosterMembers(session, staleTeam).map((m) => m.id).toList(),
        ['team-lead', 'architect', 'builder-0', 'builder-1', 'reviewer'],
      );
    },
  );

  test(
    'createSession omits mixed instances without targets when initialized',
    () async {
      final tmp = await Directory.systemTemp.createTemp(
        'fs_session_repo_omit_',
      );
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

      final session = (await repo.createSession(
        ws.workspaceId,
        sessionTeam: 'team-a',
        rosterMembers: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'Dev', replicas: 2),
        ],

        memberClis: const {'team-lead': CliTool.claude, 'dev': CliTool.claude},
      )).session;

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

      final session = (await repo.createSession(
        ws.workspaceId,
        sessionTeam: 'team-1',
        rosterMembers: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'Dev', replicas: 2),
        ],

        memberClis: const {'team-lead': CliTool.claude, 'dev': CliTool.claude},
      )).session;

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

      final session = (await repo.createSession(
        ws.workspaceId,
        sessionTeam: 'team-1',
        rosterMembers: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'Dev', replicas: 2),
        ],

        memberClis: const {'team-lead': CliTool.claude, 'dev': CliTool.claude},
      )).session;

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
    final tmp = await Directory.systemTemp.createTemp(
      'fs_session_repo_uninit_',
    );
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

        memberClis: const {'team-lead': CliTool.claude},
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

  test(
    'loadWorkspaces infers mixed placement init from valid remembered targets',
    () async {
      final tmp = await Directory.systemTemp.createTemp(
        'fs_session_repo_infer_',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SessionRepository(rootDir: tmp.path);

      final ws = await repo.createWorkspace([
        const WorkspaceFolder(path: '/local'),
        const WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ]);
      // Persist targets without the init flag (pre-migration / old manifests).
      await repo.updateWorkspaceMemberTargets(
        ws.workspaceId,
        'team-a',
        targets: const {'team-lead': 'local', 'dev-0': 'ssh:p1'},
      );

      final before = (await repo.loadWorkspaces()).single;
      expect(before.memberPlacementInitializedByTeam['team-a'], isTrue);
      expect(before.memberTargetsByTeam['team-a'], {
        'team-lead': 'local',
        'dev-0': 'ssh:p1',
      });

      // Infer is in-memory only — disk still lacks the flag until an explicit save.
      final reloaded = SessionRepository(rootDir: tmp.path);
      final again = (await reloaded.loadWorkspaces()).single;
      expect(again.memberPlacementInitializedByTeam['team-a'], isTrue);
    },
  );

  test(
    'loadWorkspaces does not infer init when remembered targets are empty',
    () async {
      final tmp = await Directory.systemTemp.createTemp(
        'fs_session_repo_infer_empty_',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SessionRepository(rootDir: tmp.path);

      final ws = await repo.createWorkspace([
        const WorkspaceFolder(path: '/local'),
        const WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ]);

      final loaded = (await repo.loadWorkspaces()).single;
      expect(loaded.workspaceId, ws.workspaceId);
      expect(loaded.memberPlacementInitializedByTeam, isEmpty);
    },
  );

  test(
    'loadWorkspaces does not infer init when a target id is unknown',
    () async {
      final tmp = await Directory.systemTemp.createTemp(
        'fs_session_repo_infer_bad_',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SessionRepository(rootDir: tmp.path);

      final ws = await repo.createWorkspace([
        const WorkspaceFolder(path: '/local'),
        const WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ]);
      await repo.updateWorkspaceMemberTargets(
        ws.workspaceId,
        'team-a',
        targets: const {'team-lead': 'ssh:gone'},
      );

      final loaded = (await repo.loadWorkspaces()).single;
      expect(loaded.memberPlacementInitializedByTeam['team-a'], isNot(true));
    },
  );
}
