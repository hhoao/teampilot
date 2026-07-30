import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/team/team_roster_editor.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/team/default_workspace_service.dart';
import 'package:teampilot/utils/workspace/workspace_path_utils.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  late Directory base;

  setUp(() async {
    setUpTestAppStorage();
    base = Directory.systemTemp.createTempSync('default_workspace_');
    DefaultWorkspaceDirectory.setForTesting(p.join(base.path, 'Documents'));
  });

  tearDown(() {
    tearDownTestAppStorage();
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  test(
    'seed creates Default workspace with personal and team sessions',
    () async {
      final repo = SessionRepository();
      final team = const TeamRosterEditor().defaultNativeTeam();

      final workspace = await DefaultWorkspaceService.seed(
        repo,
        defaultTeam: team,
      );

      expect(workspace.display, DefaultWorkspaceService.defaultDisplay);
      expect(
        workspace.firstFolderPath,
        normalizeWorkspacePath(p.join(base.path, 'Documents', 'TeamPilot')),
      );
      expect(workspace.defaultProfileId, isEmpty);

      final sessions = await repo.loadSessions();
      final workspaceSessions = sessions
          .where((s) => s.workspaceId == workspace.workspaceId)
          .toList();
      expect(workspaceSessions, hasLength(2));

      final personal = workspaceSessions.singleWhere(
        (s) => s.sessionTeam.isEmpty,
      );
      expect(personal.profileId, isEmpty);

      final teamSession = workspaceSessions.singleWhere(
        (s) => s.sessionTeam == team.id,
      );
      expect(teamSession.members, isNotEmpty);
    },
  );

  test('seed is idempotent', () async {
    final repo = SessionRepository();
    final team = const TeamRosterEditor().defaultNativeTeam();

    await DefaultWorkspaceService.seed(repo, defaultTeam: team);
    await DefaultWorkspaceService.seed(repo, defaultTeam: team);

    final workspaces = await repo.loadWorkspaces();
    expect(workspaces, hasLength(1));
    final sessions = await repo.loadSessions();
    expect(
      sessions.where((s) => s.workspaceId == workspaces.single.workspaceId),
      hasLength(2),
    );
  });

  test('ensureDefault stamps ssh home as folder targetId', () async {
    final repo = SessionRepository();
    final team = const TeamRosterEditor().defaultNativeTeam();
    final home = RuntimeTarget.ssh('p1', label: 'box');

    await DefaultWorkspaceService.ensureDefault(
      repo,
      defaultTeam: team,
      home: home,
    );

    final workspaces = await repo.loadWorkspaces();
    expect(workspaces, isNotEmpty);
    expect(workspaces.first.folders.first.targetId, 'ssh:p1');
  });

  test('ensureDefault uses home/TeamPilot path for ssh home', () async {
    final remoteHome = Directory(p.join(base.path, 'remote-home'))
      ..createSync();
    final appData = Directory(p.join(base.path, 'app-data'))..createSync();
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(remoteHome.path),
      ),
      paths: AppPaths(appData.path),
      home: remoteHome.path,
      cwd: remoteHome.path,
    );
    DefaultWorkspaceDirectory.setForTesting(p.join(base.path, 'Documents'));

    final repo = SessionRepository();
    final team = const TeamRosterEditor().defaultNativeTeam();
    final home = RuntimeTarget.ssh('p1', label: 'box');

    await DefaultWorkspaceService.ensureDefault(
      repo,
      defaultTeam: team,
      home: home,
    );

    final workspaces = await repo.loadWorkspaces();
    expect(workspaces, isNotEmpty);
    expect(
      workspaces.first.folders.first.path,
      normalizeWorkspacePath(p.join(remoteHome.path, 'TeamPilot')),
    );
    expect(workspaces.first.folders.first.targetId, 'ssh:p1');
    expect(Directory(p.join(remoteHome.path, 'TeamPilot')).existsSync(), isTrue);
  });

  test('ensureDefault uses home/TeamPilot path for termux home', () async {
    final termuxHome = Directory(p.join(base.path, 'termux-home'))
      ..createSync();
    final appData = Directory(p.join(base.path, 'termux-app-data'))
      ..createSync();
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(termuxHome.path),
      ),
      paths: AppPaths(appData.path),
      home: termuxHome.path,
      cwd: termuxHome.path,
    );
    DefaultWorkspaceDirectory.setForTesting(p.join(base.path, 'Documents'));

    final repo = SessionRepository();
    final team = const TeamRosterEditor().defaultNativeTeam();
    final home = RuntimeTarget.termux();

    await DefaultWorkspaceService.ensureDefault(
      repo,
      defaultTeam: team,
      home: home,
    );

    final workspaces = await repo.loadWorkspaces();
    expect(workspaces, isNotEmpty);
    expect(
      workspaces.first.folders.first.path,
      normalizeWorkspacePath(p.join(termuxHome.path, 'TeamPilot')),
    );
    expect(workspaces.first.folders.first.targetId, 'termux:default');
    expect(
      Directory(p.join(termuxHome.path, 'TeamPilot')).existsSync(),
      isTrue,
    );
  });

  test('ensureDefault is idempotent and reports no mutation', () async {
    final repo = SessionRepository();
    final team = const TeamRosterEditor().defaultNativeTeam();

    final first = await DefaultWorkspaceService.ensureDefault(
      repo,
      defaultTeam: team,
    );
    expect(first, isTrue);

    final workspaces = await repo.loadWorkspaces();
    final again = await DefaultWorkspaceService.ensureDefault(
      repo,
      defaultTeam: team,
      knownWorkspaces: workspaces,
    );
    expect(again, isFalse);
  });
}
