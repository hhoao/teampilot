import 'dart:io';

import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:flutter_test/flutter_test.dart';

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
      final project = await repo.createProject('/tmp/my-project');
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

  test('deleteProject removes project and session files', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final project = await repo.createProject('/a');
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
    'createProject merges additionalPaths and display for same primaryPath',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final p1 = await repo.createProject(
        '/root',
        additionalPaths: const ['/a'],
      );
      expect(p1.additionalPaths, ['/a']);

      final p2 = await repo.createProject(
        '/root',
        additionalPaths: const ['/b', '/a'],
        display: 'My display',
      );
      expect(p2.projectId, p1.projectId);
      expect(p2.additionalPaths, ['/a', '/b']);
      expect(p2.display, 'My display');
    },
  );

  test('updateProjectPaths updates index', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final p = await repo.createProject('/old');
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
      final p = await repo.createProject('/p', additionalPaths: const ['/q']);
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
    final project = await repo.createProject('/z');
    final good = await repo.createSession(project.projectId);
    final badFile = File('${tmp.path}/sessions/bogus.json');
    await badFile.parent.create(recursive: true);
    await badFile.writeAsString('{ not json');

    final list = await repo.loadSessions();
    expect(list.length, 1);
    expect(list.single.sessionId, good.sessionId);
  });

  test(
    'markSessionLaunched writes launchTeam and started without changing empty sessionTeam',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final project = await repo.createProject('/w');
      final session = await repo.createSession(project.projectId);
      await repo.markSessionLaunched(
        session.sessionId,
        launchTeam: 'my-cli-team',
      );

      final disk = (await repo.loadSessions()).single;
      expect(disk.launchState, AppSessionLaunchState.started);
      expect(disk.launchTeam, 'my-cli-team');
      expect(disk.sessionTeam, '');
    },
  );

  test('createSession persists sessionTeam when provided', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final project = await repo.createProject('/w');
    final session = await repo.createSession(
      project.projectId,
      sessionTeam: 'team-config-id-1',
    );
    expect(session.sessionTeam, 'team-config-id-1');
    final disk = (await repo.loadSessions()).single;
    expect(disk.sessionTeam, 'team-config-id-1');
    expect(disk.launchTeam, '');
  });

  test('markSessionLaunched keeps sessionTeam and sets launchTeam', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final project = await repo.createProject('/w');
    final session = await repo.createSession(
      project.projectId,
      sessionTeam: 'ui-team-id',
    );
    await repo.markSessionLaunched(session.sessionId, launchTeam: 'cli-dir');

    final disk = (await repo.loadSessions()).single;
    expect(disk.sessionTeam, 'ui-team-id');
    expect(disk.launchTeam, 'cli-dir');
    expect(disk.launchState, AppSessionLaunchState.started);
  });

  test(
    'parallel updateSessionTeam and markSessionStarted do not drop fields',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final project = await repo.createProject('/w');
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
    final project = await repo.createProject('/w');
    final session = await repo.createSession(project.projectId);
    await repo.updateSessionTeam(session.sessionId, 't1');
    expect((await repo.loadSessions()).single.sessionTeam, 't1');
    await repo.updateSessionTeam(session.sessionId, 't2');
    expect((await repo.loadSessions()).single.sessionTeam, 't2');
  });
}
