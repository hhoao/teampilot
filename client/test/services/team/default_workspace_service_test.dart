import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/team/team_roster_editor.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';
import 'package:teampilot/services/team/default_workspace_service.dart';
import 'package:teampilot/utils/workspace_path_utils.dart';

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

  test('seed creates Default workspace with personal and team sessions', () async {
    final repo = SessionRepository();
    final team = const TeamRosterEditor().defaultTeam();

    final workspace = await DefaultWorkspaceService.seed(
      repo,
      defaultTeam: team,
    );

    expect(workspace.display, DefaultWorkspaceService.defaultDisplay);
    expect(
      workspace.primaryPath,
      normalizeWorkspacePath(p.join(base.path, 'Documents', 'TeamPilot')),
    );
    expect(
      workspace.defaultProfileId,
      LaunchProfileProvisioner.defaultPersonalId,
    );

    final sessions = await repo.loadSessions();
    final workspaceSessions =
        sessions.where((s) => s.workspaceId == workspace.workspaceId).toList();
    expect(workspaceSessions, hasLength(2));

    final personal = workspaceSessions.singleWhere((s) => s.sessionTeam.isEmpty);
    expect(personal.profileId, LaunchProfileProvisioner.defaultPersonalId);

    final teamSession =
        workspaceSessions.singleWhere((s) => s.sessionTeam == team.id);
    expect(teamSession.members, isNotEmpty);
  });

  test('seed is idempotent', () async {
    final repo = SessionRepository();
    final team = const TeamRosterEditor().defaultTeam();

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
}
