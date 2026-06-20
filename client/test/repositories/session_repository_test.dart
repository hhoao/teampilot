import 'dart:io';

import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_icon_ref.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingLifecycleService extends SessionLifecycleService {
  _RecordingLifecycleService()
    : super(appDataBasePath: Directory.systemTemp.path);

  final destroyed = <({String teamId, String sessionId})>[];

  @override
  Future<void> destroyCliState({
    required String workspaceId,
    required String teamId,
    required String sessionId,
  }) async {
    destroyed.add((teamId: teamId, sessionId: sessionId));
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
      final workspace = await repo.createWorkspace('/tmp/my-workspace');
      expect(workspace.primaryPath, '/tmp/my-workspace');

      final session = await repo.createSession(workspace.workspaceId);
      expect(session.workspaceId, workspace.workspaceId);
      expect(session.primaryPath, '/tmp/my-workspace');
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

  test('createSession prepends sessionId without bumping workspace updatedAt', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace('/a');
    final s1 = await repo.createSession(workspace.workspaceId);
    final afterFirst = (await repo.loadWorkspaces()).single;
    final s2 = await repo.createSession(workspace.workspaceId);
    final afterSecond = (await repo.loadWorkspaces()).single;

    expect(afterSecond.sessionIds, [s2.sessionId, s1.sessionId]);
    expect(afterSecond.updatedAt, afterFirst.updatedAt);
  });

  test('deleteWorkspace removes workspace and session files', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace('/a');
    final s1 = await repo.createSession(workspace.workspaceId);
    final s2 = await repo.createSession(workspace.workspaceId);

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
      final workspace = await repo.createWorkspace('/a');
      final session = await repo.createSession(
        workspace.workspaceId,
        sessionTeam: 'team-a',
        rosterMembers: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        ],
      );

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
    final workspace = await repo.createWorkspace('/a');
    const roster = [TeamMemberConfig(id: 'team-lead', name: 'team-lead')];
    final s1 = await repo.createSession(
      workspace.workspaceId,
      sessionTeam: 'T',
      rosterMembers: roster,
    );
    final s2 = await repo.createSession(
      workspace.workspaceId,
      sessionTeam: 'T',
      rosterMembers: roster,
    );

    await repo.deleteWorkspace(workspace.workspaceId);

    // createSession prepends sessionIds, so deleteWorkspace destroys newest first.
    expect(lifecycle.destroyed, [
      (teamId: 'T', sessionId: s2.sessionId),
      (teamId: 'T', sessionId: s1.sessionId),
    ]);
  });

  test(
    'createWorkspace merges additionalPaths and display for same primaryPath',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final p1 = await repo.createWorkspace(
        '/root',
        additionalPaths: const ['/a'],
      );
      expect(p1.additionalPaths, ['/a']);

      final p2 = await repo.createWorkspace(
        '/root',
        additionalPaths: const ['/b', '/a'],
        display: 'My display',
      );
      expect(p2.workspaceId, p1.workspaceId);
      expect(p2.additionalPaths, ['/a', '/b']);
      expect(p2.display, 'My display');
    },
  );

  test('createWorkspace reuses same primary path', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final a = await repo.createWorkspace('/shared');
    final b = await repo.createWorkspace('/shared');

    expect(a.workspaceId, b.workspaceId);
    expect((await repo.loadWorkspaces()).length, 1);
  });

  test('createWorkspace allowDuplicate creates distinct same-path workspace',
      () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final a = await repo.createWorkspace('/shared', display: 'First');
    final b = await repo.createWorkspace(
      '/shared',
      display: 'Second',
      allowDuplicate: true,
    );

    expect(a.workspaceId, isNot(b.workspaceId));
    expect(a.primaryPath, b.primaryPath);
    final loaded = await repo.loadWorkspaces();
    expect(loaded.length, 2);
    expect(loaded.map((w) => w.display).toSet(), {'First', 'Second'});
  });

  test('updateWorkspaceMetadata updates display and additionalPaths', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final p = await repo.createWorkspace('/base', additionalPaths: const ['/a']);
    await repo.updateWorkspaceMetadata(
      p.workspaceId,
      display: 'My App',
      additionalPaths: const ['/b'],
    );
    final loaded = await repo.loadWorkspaces();
    expect(loaded.single.display, 'My App');
    expect(loaded.single.additionalPaths, ['/b']);
  });

  test('applyWorkspaceIcon persists preset and auto icons', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final p = await repo.createWorkspace('/base');
    expect(p.icon, WorkspaceIconRef.auto);

    await repo.applyWorkspaceIcon(p.workspaceId, const WorkspaceIconPreset(5));
    var loaded = (await repo.loadWorkspaces()).single;
    expect(loaded.icon, const WorkspaceIconPreset(5));

    await repo.applyWorkspaceIcon(p.workspaceId, WorkspaceIconRef.auto);
    loaded = (await repo.loadWorkspaces()).single;
    expect(loaded.icon, WorkspaceIconRef.auto);
  });

  test('importCustomWorkspaceIcon persists file and preset clears custom', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final iconFile = File('${tmp.path}/picked.png');
    await iconFile.writeAsBytes([0x89, 0x50, 0x4E, 0x47]);

    final repo = SessionRepository(rootDir: tmp.path);
    final p = await repo.createWorkspace('/base');
    await repo.importCustomWorkspaceIcon(p.workspaceId, iconFile.path);

    var loaded = (await repo.loadWorkspaces()).single;
    expect(loaded.icon, WorkspaceIconCustom('assets/icon.png'));

    await repo.applyWorkspaceIcon(p.workspaceId, const WorkspaceIconPreset(2));
    loaded = (await repo.loadWorkspaces()).single;
    expect(loaded.icon, const WorkspaceIconPreset(2));
  });

  test('updateWorkspacePaths updates index', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final p = await repo.createWorkspace('/old');
    await repo.updateWorkspacePaths(p.workspaceId, '/new', ['/x']);
    final loaded = await repo.loadWorkspaces();
    expect(loaded.single.primaryPath, '/new');
    expect(loaded.single.additionalPaths, ['/x']);
  });

  test(
    'createSession snapshots workspace additionalPaths at creation time',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final p = await repo.createWorkspace('/p', additionalPaths: const ['/q']);
      final s1 = await repo.createSession(p.workspaceId);
      expect(s1.additionalPaths, ['/q']);

      await repo.updateWorkspacePaths(p.workspaceId, '/p', ['/r']);
      final s2 = await repo.createSession(p.workspaceId);
      expect(s2.additionalPaths, ['/r']);
      final s1Reload = (await repo.loadSessions()).firstWhere(
        (e) => e.sessionId == s1.sessionId,
      );
      expect(s1Reload.additionalPaths, ['/q']);
    },
  );

  test('loadSessions skips corrupt json files', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace('/z');
    final good = await repo.createSession(workspace.workspaceId);
    final badDir = Directory(
      '${tmp.path}/workspace/workspaces/${workspace.workspaceId}/sessions/bogus',
    );
    await badDir.create(recursive: true);
    await File('${badDir.path}/session.json').writeAsString('{ not json');

    final list = await repo.loadSessions();
    expect(list.length, 1);
    expect(list.single.sessionId, good.sessionId);
  });

  test('markSessionLaunched sets started without changing sessionTeam', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace('/w');
    final session = await repo.createSession(workspace.workspaceId);
    await repo.markSessionLaunched(session.sessionId);

    final disk = (await repo.loadSessions()).single;
    expect(disk.launchState, AppSessionLaunchState.started);
    expect(disk.sessionTeam, '');
    expect(disk.cliTeamName, '');
  });

  test('createSession persists sessionTeam when provided', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace('/w');
    final session = await repo.createSession(
      workspace.workspaceId,
      sessionTeam: 'team-config-id-1',
      rosterMembers: const [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      ],
    );
    expect(session.sessionTeam, 'team-config-id-1');
    expect(session.cliTeamName, 'team-config-id-1-1');
    expect(session.members.length, 1);
    final disk = (await repo.loadSessions()).single;
    expect(disk.sessionTeam, 'team-config-id-1');
    expect(disk.cliTeamName, 'team-config-id-1-1');
  });

  test(
    'team session gets cliTeamName and per-member taskIds',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace('/w');
      const roster = [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'worker', name: 'worker'),
      ];
      final s = await repo.createSession(
        workspace.workspaceId,
        sessionTeam: 'team-a',
        rosterMembers: roster,
      );
      expect(s.cliTeamName, 'team-a-1');
      expect(s.members.length, 2);
      expect(s.members.map((b) => b.taskId).toSet().length, 2);
    },
  );

  test('ensureMemberBinding appends binding for new roster member', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace('/w');
    final session = await repo.createSession(
      workspace.workspaceId,
      sessionTeam: 'team-a',
      rosterMembers: const [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      ],
    );
    final binding = await repo.ensureMemberBinding(
      session.sessionId,
      'new-member',
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
      final workspace = await repo.createWorkspace('/w');
      final session = await repo.createSession(workspace.workspaceId);
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
    final workspace = await repo.createWorkspace('/w');
    final session = await repo.createSession(workspace.workspaceId);
    await repo.updateSessionTeam(session.sessionId, 't1');
    expect((await repo.loadSessions()).single.sessionTeam, 't1');
    await repo.updateSessionTeam(session.sessionId, 't2');
    expect((await repo.loadSessions()).single.sessionTeam, 't2');
  });

  test('personal session persists its launch profileId', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace('/w');
    final session = await repo.createSession(
      workspace.workspaceId,
      personalIdentityId: 'writing',
    );

    // In memory and after reload from disk.
    expect(session.profileId, 'writing');
    expect((await repo.loadSessions()).single.profileId, 'writing');
  });

  test('team session ignores personalIdentityId (profileId stays empty)',
      () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace('/w');
    final session = await repo.createSession(
      workspace.workspaceId,
      sessionTeam: 'team-a',
      personalIdentityId: 'writing',
      rosterMembers: [
        const TeamMemberConfig(id: 'team-lead', name: 'Lead'),
      ],
    );

    expect(session.profileId, '');
    expect((await repo.loadSessions()).single.profileId, '');
  });
}
