import 'dart:convert';
import 'dart:io';

import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_icon_ref.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingLifecycleService extends SessionLifecycleService {
  _RecordingLifecycleService()
    : super(appDataBasePath: Directory.systemTemp.path);

  final destroyed = <({String teamId, String sessionId})>[];

  final destroyedWithTarget = <String>[];

  @override
  Future<void> destroyCliState({
    required String workspaceId,
    required String teamId,
    required String sessionId,
    AppSession? session,
  }) async {
    destroyed.add((teamId: teamId, sessionId: sessionId));
    if (session != null && session.folders.isNotEmpty) {
      destroyedWithTarget.add(session.folders.first.targetId);
    }
  }
}

void main() {
  test('empty root yields empty workspaces and sessions', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    expect(await repo.loadWorkspaces(), isEmpty);
    expect(await repo.loadSessions(), isEmpty);
  });

  test(
    'createWorkspace, createSession, markSessionStarted, deleteSession',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/tmp/my-workspace'),
      ]);
      expect(workspace.firstFolderPath, '/tmp/my-workspace');

      final session = (await repo.createSession(workspace.workspaceId)).session;
      expect(session.workspaceId, workspace.workspaceId);
      expect(session.firstFolderPath, '/tmp/my-workspace');
      expect(session.launchState, AppSessionLaunchState.created);

      var workspaces = await repo.loadWorkspaces();
      expect(workspaces.single.sessionIds, contains(session.sessionId));

      await repo.markSessionStarted(session.sessionId);
      final reloaded = await repo.loadSessions();
      expect(reloaded.single.launchState, AppSessionLaunchState.started);

      await repo.renameSession(session.sessionId, 'Renamed');
      expect((await repo.loadSessions()).single.display, 'Renamed');

      await repo.deleteSession(session.sessionId);
      expect(await repo.loadSessions(), isEmpty);
      workspaces = await repo.loadWorkspaces();
      expect(workspaces.single.sessionIds, isEmpty);
    },
  );

  test(
    'createSession prepends sessionId without bumping workspace updatedAt',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/a'),
      ]);
      final s1 = (await repo.createSession(workspace.workspaceId)).session;
      final afterFirst = (await repo.loadWorkspaces()).single;
      final s2 = (await repo.createSession(workspace.workspaceId)).session;
      final afterSecond = (await repo.loadWorkspaces()).single;

      expect(afterSecond.sessionIds, [s2.sessionId, s1.sessionId]);
      expect(afterSecond.updatedAt, afterFirst.updatedAt);
    },
  );

  test('deleteWorkspace removes workspace and session files', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/a')]);
    final s1 = (await repo.createSession(workspace.workspaceId)).session;
    final s2 = (await repo.createSession(workspace.workspaceId)).session;

    await repo.deleteWorkspace(workspace.workspaceId);
    expect(await repo.loadWorkspaces(), isEmpty);
    expect(await repo.loadSessions(), isEmpty);
    expect(
      Directory(
        '${tmp.path}/workspace/workspaces/${workspace.workspaceId}/sessions/${s1.sessionId}',
      ).existsSync(),
      isFalse,
    );
    expect(
      Directory(
        '${tmp.path}/workspace/workspaces/${workspace.workspaceId}/sessions/${s2.sessionId}',
      ).existsSync(),
      isFalse,
    );
  });

  test(
    'deleteSession destroys CLI state before removing session metadata',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final lifecycle = _RecordingLifecycleService();
      final repo = SessionRepository(
        rootDir: tmp.path,
        lifecycleService: lifecycle,
      );
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/a'),
      ]);
      final session = (await repo.createSession(
        workspace.workspaceId,
        sessionTeam: 'team-a',
        rosterMembers: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        ],

        memberClis: const {'team-lead': CliTool.claude},
      )).session;

      await repo.deleteSession(session.sessionId);

      expect(lifecycle.destroyed, [
        (teamId: 'team-a', sessionId: session.sessionId),
      ]);
    },
  );

  test('deleteWorkspace cascades CLI state for all workspace sessions', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final lifecycle = _RecordingLifecycleService();
    final repo = SessionRepository(
      rootDir: tmp.path,
      lifecycleService: lifecycle,
    );
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/a')]);
    const roster = [TeamMemberConfig(id: 'team-lead', name: 'team-lead')];
    final s1 = (await repo.createSession(
      workspace.workspaceId,
      sessionTeam: 'T',
      rosterMembers: roster,

      memberClis: {for (final m in roster) m.id: CliTool.claude},
    )).session;
    final s2 = (await repo.createSession(
      workspace.workspaceId,
      sessionTeam: 'T',
      rosterMembers: roster,

      memberClis: {for (final m in roster) m.id: CliTool.claude},
    )).session;

    await repo.deleteWorkspace(workspace.workspaceId);

    // createSession prepends sessionIds, so deleteWorkspace destroys newest first.
    expect(lifecycle.destroyed, [
      (teamId: 'T', sessionId: s2.sessionId),
      (teamId: 'T', sessionId: s1.sessionId),
    ]);
  });

  test('createWorkspace always creates a new workspace (no dedup)', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final a = await repo.createWorkspace([const WorkspaceFolder(path: '/p')]);
    final b = await repo.createWorkspace([const WorkspaceFolder(path: '/p')]);
    expect(a.workspaceId, isNot(equals(b.workspaceId)));
    expect((await repo.loadWorkspaces()).length, 2);
  });

  test('updateWorkspaceMetadata updates display', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final p = await repo.createWorkspace([
      WorkspaceFolder(path: '/base'),
      WorkspaceFolder(path: '/a'),
    ]);
    await repo.updateWorkspaceMetadata(p.workspaceId, display: 'My App');
    final loaded = await repo.loadWorkspaces();
    expect(loaded.single.display, 'My App');
    expect(loaded.single.extraFolderPaths, ['/a']);
  });

  test('updateWorkspaceMetadata persists rootSandboxEnvOptIn', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final p = await repo.createWorkspace([WorkspaceFolder(path: '/base')]);
    expect(p.rootSandboxEnvOptIn, isFalse);

    await repo.updateWorkspaceMetadata(
      p.workspaceId,
      rootSandboxEnvOptIn: true,
    );
    final loaded = await repo.loadWorkspaces();
    expect(loaded.single.rootSandboxEnvOptIn, isTrue);
  });

  test('applyWorkspaceIcon persists preset and auto icons', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final p = await repo.createWorkspace([WorkspaceFolder(path: '/base')]);
    expect(p.icon, WorkspaceIconRef.auto);

    await repo.applyWorkspaceIcon(p.workspaceId, const WorkspaceIconPreset(5));
    var loaded = (await repo.loadWorkspaces()).single;
    expect(loaded.icon, const WorkspaceIconPreset(5));

    await repo.applyWorkspaceIcon(p.workspaceId, WorkspaceIconRef.auto);
    loaded = (await repo.loadWorkspaces()).single;
    expect(loaded.icon, WorkspaceIconRef.auto);
  });

  test(
    'importCustomWorkspaceIcon persists file and preset clears custom',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final iconFile = File('${tmp.path}/picked.png');
      await iconFile.writeAsBytes([0x89, 0x50, 0x4E, 0x47]);

      final repo = SessionRepository(rootDir: tmp.path);
      final p = await repo.createWorkspace([WorkspaceFolder(path: '/base')]);
      await repo.importCustomWorkspaceIcon(p.workspaceId, iconFile.path);

      var loaded = (await repo.loadWorkspaces()).single;
      expect(loaded.icon, WorkspaceIconCustom('assets/icon.png'));

      await repo.applyWorkspaceIcon(
        p.workspaceId,
        const WorkspaceIconPreset(2),
      );
      loaded = (await repo.loadWorkspaces()).single;
      expect(loaded.icon, const WorkspaceIconPreset(2));
    },
  );

  test('updateWorkspaceFolders updates index', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final p = await repo.createWorkspace([WorkspaceFolder(path: '/old')]);
    await repo.updateWorkspaceFolders(p.workspaceId, [
      WorkspaceFolder(path: '/new'),
      WorkspaceFolder(path: '/x'),
    ]);
    final loaded = await repo.loadWorkspaces();
    expect(loaded.single.firstFolderPath, '/new');
    expect(loaded.single.extraFolderPaths, ['/x']);
  });

  test(
    'createSession snapshots workspace additionalPaths at creation time',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final p = await repo.createWorkspace([
        WorkspaceFolder(path: '/p'),
        WorkspaceFolder(path: '/q'),
      ]);
      final s1 = (await repo.createSession(p.workspaceId)).session;
      expect(s1.extraFolderPaths, ['/q']);

      await repo.updateWorkspaceFolders(p.workspaceId, [
        WorkspaceFolder(path: '/p'),
        WorkspaceFolder(path: '/r'),
      ]);
      final s2 = (await repo.createSession(p.workspaceId)).session;
      expect(s2.extraFolderPaths, ['/r']);
      final s1Reload = (await repo.loadSessions()).firstWhere(
        (e) => e.sessionId == s1.sessionId,
      );
      expect(s1Reload.extraFolderPaths, ['/q']);
    },
  );

  test('loadSessions skips corrupt json files', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/z')]);
    final good = (await repo.createSession(workspace.workspaceId)).session;
    final badDir = Directory(
      '${tmp.path}/workspace/workspaces/${workspace.workspaceId}/sessions/bogus',
    );
    await badDir.create(recursive: true);
    await File('${badDir.path}/session.json').writeAsString('{ not json');

    final list = await repo.loadSessions();
    expect(list.length, 1);
    expect(list.single.sessionId, good.sessionId);
  });

  test(
    'markSessionLaunched sets started without changing sessionTeam',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/w'),
      ]);
      final session = (await repo.createSession(workspace.workspaceId)).session;
      await repo.markSessionLaunched(session.sessionId);

      final disk = (await repo.loadSessions()).single;
      expect(disk.launchState, AppSessionLaunchState.started);
      expect(disk.sessionTeam, '');
      expect(disk.cliTeamName, '');
    },
  );

  test('createSession persists sessionTeam when provided', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/w')]);
    final session = (await repo.createSession(
      workspace.workspaceId,
      sessionTeam: 'team-config-id-1',
      rosterMembers: const [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      ],

      memberClis: const {'team-lead': CliTool.claude},
    )).session;
    expect(session.sessionTeam, 'team-config-id-1');
    expect(session.cliTeamName, 'team-config-id-1-1');
    expect(session.members.length, 1);
    final disk = (await repo.loadSessions()).single;
    expect(disk.sessionTeam, 'team-config-id-1');
    expect(disk.cliTeamName, 'team-config-id-1-1');
  });

  test('team session gets cliTeamName and per-member taskIds', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/w')]);
    const roster = [
      TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      TeamMemberConfig(id: 'worker', name: 'worker'),
    ];
    final s = (await repo.createSession(
      workspace.workspaceId,
      sessionTeam: 'team-a',
      rosterMembers: roster,

      memberClis: {for (final m in roster) m.id: CliTool.claude},
    )).session;
    expect(s.cliTeamName, 'team-a-1');
    expect(s.members.length, 2);
    expect(s.members.map((b) => b.taskId).toSet().length, 2);
  });

  test('ensureMemberBinding appends binding for new roster member', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/w')]);
    final session = (await repo.createSession(
      workspace.workspaceId,
      sessionTeam: 'team-a',
      rosterMembers: const [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      ],
      memberClis: const {'team-lead': CliTool.claude},
    )).session;
    final binding = await repo.ensureMemberBinding(
      session.sessionId,
      'new-member',
      cli: CliTool.claude,
    );
    expect(binding.rosterMemberId, 'new-member');
    expect(binding.taskId, isNotEmpty);
    final disk = (await repo.loadSessions()).single;
    expect(disk.members.length, 2);
    expect(disk.bindingFor('new-member')?.taskId, binding.taskId);
  });

  test(
    'parallel updateSessionTeam and markSessionStarted do not drop fields',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/w'),
      ]);
      final session = (await repo.createSession(workspace.workspaceId)).session;
      await Future.wait([
        repo.updateSessionTeam(session.sessionId, 'team-x'),
        repo.markSessionStarted(session.sessionId),
      ]);
      final disk = (await repo.loadSessions()).single;
      expect(disk.launchState, AppSessionLaunchState.started);
      expect(disk.sessionTeam, 'team-x');
    },
  );

  test('updateSessionTeam reloads from disk', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/w')]);
    final session = (await repo.createSession(workspace.workspaceId)).session;
    await repo.updateSessionTeam(session.sessionId, 't1');
    expect((await repo.loadSessions()).single.sessionTeam, 't1');
    await repo.updateSessionTeam(session.sessionId, 't2');
    expect((await repo.loadSessions()).single.sessionTeam, 't2');
  });

  test('simple session persists empty profileId', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/w')]);
    final session = (await repo.createSession(workspace.workspaceId)).session;

    // Simple / unteamed sessions have no launch-profile identity.
    expect(session.profileId, '');
    expect((await repo.loadSessions()).single.profileId, '');
  });

  test('team session keeps profileId empty', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/w')]);
    final session = (await repo.createSession(
      workspace.workspaceId,
      sessionTeam: 'team-a',
      rosterMembers: [const TeamMemberConfig(id: 'team-lead', name: 'Lead')],
      memberClis: const {'team-lead': CliTool.claude},
    )).session;

    expect(session.profileId, '');
    expect((await repo.loadSessions()).single.profileId, '');
  });

  test(
    'loadWorkspacesIndex reads fresh workspaces-index.json snapshot',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/a'),
      ]);
      final session = (await repo.createSession(workspace.workspaceId)).session;

      final indexPath = '${tmp.path}/workspace/workspaces-index.json';
      // Mutations maintain the snapshot incrementally.
      expect(File(indexPath).existsSync(), isTrue);

      final fromIndex = await repo.loadWorkspacesIndex();
      expect(File(indexPath).existsSync(), isTrue);
      expect(fromIndex.single.workspaceId, workspace.workspaceId);
      expect(fromIndex.single.sessionIds, [session.sessionId]);

      await repo.deleteSession(session.sessionId);
      // Session deletes patch the snapshot incrementally.
      final afterDelete = await repo.loadWorkspacesIndex();
      expect(afterDelete.single.sessionIds, isEmpty);
    },
  );

  test('deleteWorkspace removes entry from workspaces-index.json', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/a')]);
    await repo.createSession(workspace.workspaceId);

    final indexPath = '${tmp.path}/workspace/workspaces-index.json';
    expect(File(indexPath).existsSync(), isTrue);

    await repo.deleteWorkspace(workspace.workspaceId);
    // deleteWorkspace forgets the workspace in the index snapshot.
    expect(await repo.loadWorkspacesIndex(), isEmpty);
    expect(File(indexPath).existsSync(), isTrue);
    final decoded = jsonDecode(File(indexPath).readAsStringSync());
    expect((decoded as Map)['workspaces'], isEmpty);
  });

  test(
    'createSession locks each binding CLI via member type id (replicas share)',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/w'),
      ]);
      final session = (await repo.createSession(
        workspace.workspaceId,
        sessionTeam: 'team-a',
        rosterMembers: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
        ],
        memberClis: const {
          'team-lead': CliTool.claude,
          'builder': CliTool.opencode,
        },
      )).session;

      expect(session.members.map((b) => b.rosterMemberId), [
        'team-lead',
        'builder-0',
        'builder-1',
      ]);
      expect(session.bindingFor('team-lead')?.cli, CliTool.claude);
      expect(session.bindingFor('builder-0')?.cli, CliTool.opencode);
      expect(session.bindingFor('builder-1')?.cli, CliTool.opencode);
      final disk = (await repo.loadSessions()).single;
      expect(disk.bindingFor('builder-0')?.cli, CliTool.opencode);
    },
  );

  test(
    'createSession throws ArgumentError when memberClis missing for included type',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/w'),
      ]);

      await expectLater(
        () => repo.createSession(
          workspace.workspaceId,
          sessionTeam: 'team-a',
          rosterMembers: const [
            TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
            TeamMemberConfig(id: 'builder', name: 'Builder'),
          ],
          memberClis: const {'team-lead': CliTool.claude},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('missing memberClis for builder'),
          ),
        ),
      );
    },
  );

  test(
    'createSession missing memberClis does not persist targets or bump cliTeamName',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/w'),
      ]);
      final before = (await repo.loadWorkspaces()).single;
      expect(before.memberTargetsByTeam['team-a'], isNull);

      await expectLater(
        () => repo.createSession(
          workspace.workspaceId,
          sessionTeam: 'team-a',
          rosterMembers: const [
            TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
            TeamMemberConfig(id: 'builder', name: 'Builder'),
          ],
          memberClis: const {'team-lead': CliTool.claude},
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(await repo.loadSessions(), isEmpty);
      final afterFail = (await repo.loadWorkspaces()).single;
      expect(afterFail.memberTargetsByTeam['team-a'], isNull);

      final ok = (await repo.createSession(
        workspace.workspaceId,
        sessionTeam: 'team-a',
        rosterMembers: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        ],
        memberClis: const {'team-lead': CliTool.claude},
      )).session;
      // Failed attempt must not have consumed the team counter.
      expect(ok.cliTeamName, 'team-a-1');
    },
  );

  test('simple createSession ignores memberClis', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/w')]);
    final session = (await repo.createSession(
      workspace.workspaceId,
      memberClis: const {'team-lead': CliTool.cursor},
    )).session;

    expect(session.sessionTeam, '');
    expect(session.members, isEmpty);
    expect(session.cli, isNull);
  });

  test(
    'ensureMemberBinding persists cli on insert and leaves existing unchanged',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/w'),
      ]);
      final session = (await repo.createSession(
        workspace.workspaceId,
        sessionTeam: 'team-a',
        rosterMembers: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        ],
        memberClis: const {'team-lead': CliTool.claude},
      )).session;

      final first = await repo.ensureMemberBinding(
        session.sessionId,
        'new-member',
        cli: CliTool.codex,
      );
      expect(first.cli, CliTool.codex);
      expect(
        (await repo.loadSessions()).single.bindingFor('new-member')?.cli,
        CliTool.codex,
      );

      final second = await repo.ensureMemberBinding(
        session.sessionId,
        'new-member',
        cli: CliTool.cursor,
      );
      expect(second.cli, CliTool.codex);
      expect(
        (await repo.loadSessions()).single.bindingFor('new-member')?.cli,
        CliTool.codex,
      );
    },
  );

  test(
    'cloneWorkspace copies source binding cli including null legacy',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/w'),
      ]);
      const roster = [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'worker', name: 'Worker'),
      ];
      final source = (await repo.createSession(
        workspace.workspaceId,
        sessionTeam: 'team-a',
        rosterMembers: roster,
        memberClis: const {
          'team-lead': CliTool.cursor,
          'worker': CliTool.opencode,
        },
      )).session;

      // Plant a legacy null lock on worker by rewriting session.json.
      final sessionPath =
          '${tmp.path}/workspace/workspaces/${workspace.workspaceId}'
          '/sessions/${source.sessionId}/session.json';
      final raw =
          jsonDecode(File(sessionPath).readAsStringSync())
              as Map<String, dynamic>;
      final members = (raw['members'] as List).cast<Map<String, dynamic>>();
      for (final m in members) {
        if (m['rosterMemberId'] == 'worker') {
          m.remove('cli');
        }
      }
      File(sessionPath).writeAsStringSync(jsonEncode(raw));

      final cloned = await repo.cloneWorkspace(
        workspace.workspaceId,
        rosterMembers: roster,
      );
      final clonedSession = (await repo.loadSessions()).firstWhere(
        (s) => s.workspaceId == cloned.workspace.workspaceId,
      );
      expect(cloned.sessions.map((s) => s.sessionId), contains(clonedSession.sessionId));

      expect(clonedSession.bindingFor('team-lead')?.cli, CliTool.cursor);
      expect(clonedSession.bindingFor('worker')?.cli, isNull);
    },
  );

  test(
    'createSession with knownWorkspace skips scanning every session.json',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/tmp/known-ws'),
      ]);

      // Plant many sibling session dirs. A full listSessionIdsForWorkspace walk
      // would open each session.json; create with knownWorkspace must not.
      final sessionsRoot =
          '${tmp.path}/workspace/workspaces/${workspace.workspaceId}/sessions';
      for (var i = 0; i < 80; i++) {
        final dir = Directory('$sessionsRoot/seed-$i')..createSync(recursive: true);
        File('${dir.path}/session.json').writeAsStringSync(
          jsonEncode({
            'sessionId': 'seed-$i',
            'workspaceId': workspace.workspaceId,
            'createdAt': i,
            'updatedAt': i,
            'folders': [
              {'path': '/tmp/known-ws', 'targetId': 'local'},
            ],
          }),
        );
      }

      final created = (await repo.createSession(
        workspace.workspaceId,
        knownWorkspace: workspace,
      )).session;
      expect(created.workspaceId, workspace.workspaceId);
      expect(created.firstFolderPath, '/tmp/known-ws');

      final indexed = await repo.loadWorkspacesIndex();
      expect(
        indexed.singleWhere((w) => w.workspaceId == workspace.workspaceId)
            .sessionIds,
        contains(created.sessionId),
      );
    },
  );

  test('mutation keeps workspaces-index fresh for a fresh repository', () async {
    final tmp = await Directory.systemTemp.createTemp('repo_index_test_');
    final repo = SessionRepository(rootDir: tmp.path);
    final ws = await repo.createWorkspace([WorkspaceFolder(path: '/p')]);
    final created = await repo.createSession(ws.workspaceId);

    // 直接断言 index 文件内容(不依赖静态内存缓存):
    final layout = WorkspaceLayout(
      teampilotRoot: tmp.path,
      fs: LocalFilesystem(),
    );
    final raw = await File(layout.workspacesIndexFile).readAsString();
    final decoded = jsonDecode(raw) as Map<String, Object?>;
    final list = decoded['workspaces'] as List;
    expect(list, hasLength(1));
    final wsJson = list.single as Map<String, Object?>;
    expect(wsJson['sessionIds'], [created.session.sessionId]);

    // 全新实例走快路径也能读到(缓存键按 rootDir 隔离):
    final fresh = SessionRepository(rootDir: tmp.path);
    final index = await fresh.loadWorkspacesIndex();
    expect(index, hasLength(1));
    expect(index.single.sessionIds, [created.session.sessionId]);

    await repo.deleteSession(created.session.sessionId);
    final raw2 = await File(layout.workspacesIndexFile).readAsString();
    final decoded2 = jsonDecode(raw2) as Map<String, Object?>;
    final list2 = decoded2['workspaces'] as List;
    // deleteSession 只移除 sessionId;workspace 本身仍在快照中(与全量扫描一致)。
    expect(list2, hasLength(1));
    expect((list2.single as Map<String, Object?>)['sessionIds'], isEmpty);

    await repo.deleteWorkspace(ws.workspaceId);
    final fresh2 = SessionRepository(rootDir: tmp.path);
    expect(await fresh2.loadWorkspacesIndex(), isEmpty);
    await tmp.delete(recursive: true);
  });
}
