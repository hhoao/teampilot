import 'dart:io';

import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/project_icon_ref.dart';
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
    required String teamId,
    required String sessionId,
    String? runtimeSessionId,
  }) async {
    destroyed.add((teamId: teamId, sessionId: sessionId));
  }
}

void main() {
  test('empty root yields empty projects and sessions', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    expect(await repo.loadProjects(), isEmpty);
    expect(await repo.loadSessions(), isEmpty);
  });

  test(
    'createProject, createSession, markSessionStarted, deleteSession',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final project = await repo.createProject('/tmp/my-project', teamId: '');
      expect(project.primaryPath, '/tmp/my-project');

      final session = await repo.createSession(project.projectId);
      expect(session.projectId, project.projectId);
      expect(session.primaryPath, '/tmp/my-project');
      expect(session.launchState, AppSessionLaunchState.created);

      var projects = await repo.loadProjects();
      expect(projects.single.sessionIds, contains(session.sessionId));

      await repo.markSessionStarted(session.sessionId);
      final reloaded = await repo.loadSessions();
      expect(reloaded.single.launchState, AppSessionLaunchState.started);

      await repo.renameSession(session.sessionId, 'Renamed');
      expect((await repo.loadSessions()).single.display, 'Renamed');

      await repo.deleteSession(session.sessionId);
      expect(await repo.loadSessions(), isEmpty);
      projects = await repo.loadProjects();
      expect(projects.single.sessionIds, isEmpty);
    },
  );

  test('createSession prepends sessionId without bumping project updatedAt', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final project = await repo.createProject('/a', teamId: '');
    final s1 = await repo.createSession(project.projectId);
    final afterFirst = (await repo.loadProjects()).single;
    final s2 = await repo.createSession(project.projectId);
    final afterSecond = (await repo.loadProjects()).single;

    expect(afterSecond.sessionIds, [s2.sessionId, s1.sessionId]);
    expect(afterSecond.updatedAt, afterFirst.updatedAt);
  });

  test('deleteProject removes project and session files', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final project = await repo.createProject('/a', teamId: '');
    final s1 = await repo.createSession(project.projectId);
    final s2 = await repo.createSession(project.projectId);

    await repo.deleteProject(project.projectId);
    expect(await repo.loadProjects(), isEmpty);
    expect(await repo.loadSessions(), isEmpty);
    expect(
      File('${tmp.path}/sessions/${s1.sessionId}.json').existsSync(),
      isFalse,
    );
    expect(
      File('${tmp.path}/sessions/${s2.sessionId}.json').existsSync(),
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
      final project = await repo.createProject('/a', teamId: '');
      final session = await repo.createSession(
        project.projectId,
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

  test('deleteProject cascades CLI state for all project sessions', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final lifecycle = _RecordingLifecycleService();
    final repo = SessionRepository(
      rootDir: tmp.path,
      lifecycleService: lifecycle,
    );
    final project = await repo.createProject('/a', teamId: '');
    const roster = [TeamMemberConfig(id: 'team-lead', name: 'team-lead')];
    final s1 = await repo.createSession(
      project.projectId,
      sessionTeam: 'T',
      rosterMembers: roster,
    );
    final s2 = await repo.createSession(
      project.projectId,
      sessionTeam: 'T',
      rosterMembers: roster,
    );

    await repo.deleteProject(project.projectId);

    // createSession prepends sessionIds, so deleteProject destroys newest first.
    expect(lifecycle.destroyed, [
      (teamId: 'T', sessionId: s2.sessionId),
      (teamId: 'T', sessionId: s1.sessionId),
    ]);
  });

  test(
    'createProject merges additionalPaths and display for same primaryPath',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final p1 = await repo.createProject(
        '/root', teamId: '',
        additionalPaths: const ['/a'],
      );
      expect(p1.additionalPaths, ['/a']);

      final p2 = await repo.createProject(
        '/root', teamId: '',
        additionalPaths: const ['/b', '/a'],
        display: 'My display',
      );
      expect(p2.projectId, p1.projectId);
      expect(p2.additionalPaths, ['/a', '/b']);
      expect(p2.display, 'My display');
    },
  );

  test(
    'createProject keeps same path in different teams as separate projects',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final a = await repo.createProject('/shared', teamId: 'team-a');
      final b = await repo.createProject('/shared', teamId: 'team-b');

      expect(a.projectId, isNot(b.projectId));
      expect(a.teamId, 'team-a');
      expect(b.teamId, 'team-b');
      expect((await repo.loadProjects()).length, 2);

      // Same path + same team reuses the existing project.
      final aAgain = await repo.createProject('/shared', teamId: 'team-a');
      expect(aAgain.projectId, a.projectId);
      expect((await repo.loadProjects()).length, 2);
    },
  );

  test('updateProjectMetadata updates display and additionalPaths', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final p = await repo.createProject('/base', teamId: '', additionalPaths: const ['/a']);
    await repo.updateProjectMetadata(
      p.projectId,
      display: 'My App',
      additionalPaths: const ['/b'],
    );
    final loaded = await repo.loadProjects();
    expect(loaded.single.display, 'My App');
    expect(loaded.single.additionalPaths, ['/b']);
  });

  test('applyProjectIcon persists preset and auto icons', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final p = await repo.createProject('/base', teamId: '');
    expect(p.icon, ProjectIconRef.auto);

    await repo.applyProjectIcon(p.projectId, const ProjectIconPreset(5));
    var loaded = (await repo.loadProjects()).single;
    expect(loaded.icon, const ProjectIconPreset(5));

    await repo.applyProjectIcon(p.projectId, ProjectIconRef.auto);
    loaded = (await repo.loadProjects()).single;
    expect(loaded.icon, ProjectIconRef.auto);
  });

  test('importCustomProjectIcon persists file and preset clears custom', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final iconFile = File('${tmp.path}/picked.png');
    await iconFile.writeAsBytes([0x89, 0x50, 0x4E, 0x47]);

    final repo = SessionRepository(rootDir: tmp.path);
    final p = await repo.createProject('/base', teamId: '');
    await repo.importCustomProjectIcon(p.projectId, iconFile.path);

    var loaded = (await repo.loadProjects()).single;
    expect(loaded.icon, ProjectIconCustom('icons/${p.projectId}.png'));

    await repo.applyProjectIcon(p.projectId, const ProjectIconPreset(2));
    loaded = (await repo.loadProjects()).single;
    expect(loaded.icon, const ProjectIconPreset(2));
  });

  test('updateProjectPaths updates index', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final p = await repo.createProject('/old', teamId: '');
    await repo.updateProjectPaths(p.projectId, '/new', ['/x']);
    final loaded = await repo.loadProjects();
    expect(loaded.single.primaryPath, '/new');
    expect(loaded.single.additionalPaths, ['/x']);
  });

  test(
    'createSession snapshots project additionalPaths at creation time',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final p = await repo.createProject('/p', teamId: '', additionalPaths: const ['/q']);
      final s1 = await repo.createSession(p.projectId);
      expect(s1.additionalPaths, ['/q']);

      await repo.updateProjectPaths(p.projectId, '/p', ['/r']);
      final s2 = await repo.createSession(p.projectId);
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
    final project = await repo.createProject('/z', teamId: '');
    final good = await repo.createSession(project.projectId);
    final badFile = File('${tmp.path}/sessions/bogus.json');
    await badFile.parent.create(recursive: true);
    await badFile.writeAsString('{ not json');

    final list = await repo.loadSessions();
    expect(list.length, 1);
    expect(list.single.sessionId, good.sessionId);
  });

  test('markSessionLaunched sets started without changing sessionTeam', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final project = await repo.createProject('/w', teamId: '');
    final session = await repo.createSession(project.projectId);
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
    final project = await repo.createProject('/w', teamId: '');
    final session = await repo.createSession(
      project.projectId,
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
      final project = await repo.createProject('/w', teamId: '');
      const roster = [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'worker', name: 'worker'),
      ];
      final s = await repo.createSession(
        project.projectId,
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
    final project = await repo.createProject('/w', teamId: '');
    final session = await repo.createSession(
      project.projectId,
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
      final project = await repo.createProject('/w', teamId: '');
      final session = await repo.createSession(project.projectId);
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
    final project = await repo.createProject('/w', teamId: '');
    final session = await repo.createSession(project.projectId);
    await repo.updateSessionTeam(session.sessionId, 't1');
    expect((await repo.loadSessions()).single.sessionTeam, 't1');
    await repo.updateSessionTeam(session.sessionId, 't2');
    expect((await repo.loadSessions()).single.sessionTeam, 't2');
  });
}
