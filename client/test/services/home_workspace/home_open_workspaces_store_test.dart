import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';
import 'package:teampilot/models/launch_profile_ref.dart';
import 'package:teampilot/models/workspace_tab_ref.dart';
import 'package:teampilot/services/home_workspace/home_open_workspaces_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  late Directory root;
  late HomeOpenWorkspacesStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('open_workspaces_store_');
    final paths = AppPaths(root.path);
    final fs = LocalFilesystem(
      pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
    );
    store = HomeOpenWorkspacesStore(
      fs: fs,
      pathOverride: paths.homeWorkspaceOpenWorkspacesJson,
    );
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test('saveOrderedTabs persists workspace id and launch identity', () async {
    const personal = LaunchProfileRef(LaunchProfileProvisioner.defaultPersonalId);
    const team = LaunchProfileRef('team-a');
    await store.saveOrderedTabs([
      const WorkspaceTabRef(workspaceId: 'proj-a', identity: personal),
      const WorkspaceTabRef(workspaceId: 'proj-a', identity: team),
    ]);

    expect(await store.loadOrderedTabs(), [
      const WorkspaceTabRef(workspaceId: 'proj-a', identity: personal),
      const WorkspaceTabRef(workspaceId: 'proj-a', identity: team),
    ]);

    final file = File(AppPaths(root.path).homeWorkspaceOpenWorkspacesJson);
    expect(file.existsSync(), isTrue);
  });

  test('loadOrderedTabs ignores legacy workspaceIds payload', () async {
    final path = AppPaths(root.path).homeWorkspaceOpenWorkspacesJson;
    await File(path).parent.create(recursive: true);
    await File(path).writeAsString('{"workspaceIds":["proj-a","proj-b"]}');

    expect(await store.loadOrderedTabs(), isEmpty);
  });
}
