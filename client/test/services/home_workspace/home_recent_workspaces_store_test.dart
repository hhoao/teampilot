import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_profile_ref.dart';
import 'package:teampilot/models/workspace_tab_ref.dart';
import 'package:teampilot/services/home_workspace/home_recent_workspaces_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';

void main() {
  late Directory root;
  late HomeRecentWorkspacesStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('recent_workspaces_store_');
    final paths = AppPaths(root.path);
    final fs = LocalFilesystem(
      pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
    );
    store = HomeRecentWorkspacesStore(
      fs: fs,
      pathOverride: paths.homeWorkspaceRecentWorkspacesJson,
    );
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test('recordVisit keeps distinct tabs for same directory', () async {
    const personal = LaunchProfileRef(LaunchProfileProvisioner.defaultPersonalId);
    const team = LaunchProfileRef('team-a');
    const personalTab = WorkspaceTabRef(
      workspaceId: 'proj-a',
      identity: personal,
    );
    const teamTab = WorkspaceTabRef(
      workspaceId: 'proj-a',
      identity: team,
    );

    await store.recordVisit(personalTab);
    await store.recordVisit(teamTab);

    expect(await store.loadOrderedTabs(), [teamTab, personalTab]);
  });

  test('recordVisit moves existing tab key to front', () async {
    const personal = LaunchProfileRef(LaunchProfileProvisioner.defaultPersonalId);
    const team = LaunchProfileRef('team-a');
    const personalTab = WorkspaceTabRef(
      workspaceId: 'proj-a',
      identity: personal,
    );
    const teamTab = WorkspaceTabRef(
      workspaceId: 'proj-a',
      identity: team,
    );

    await store.recordVisit(personalTab);
    await store.recordVisit(teamTab);
    await store.recordVisit(personalTab);

    expect(await store.loadOrderedTabs(), [personalTab, teamTab]);
  });

  test('loadOrderedTabs ignores legacy workspaceIds payload', () async {
    final path = AppPaths(root.path).homeWorkspaceRecentWorkspacesJson;
    await File(path).parent.create(recursive: true);
    await File(path).writeAsString('{"workspaceIds":["proj-a","proj-b"]}');

    expect(await store.loadOrderedTabs(), isEmpty);
  });
}
