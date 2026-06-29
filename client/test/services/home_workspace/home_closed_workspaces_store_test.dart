import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/home_closed_workspace_entry.dart';
import 'package:teampilot/models/launch_profile_ref.dart';
import 'package:teampilot/models/workspace_topology.dart';
import 'package:teampilot/services/home_workspace/home_closed_workspaces_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';

void main() {
  late Directory root;
  late HomeClosedWorkspacesStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('closed_workspaces_store_');
    final paths = AppPaths(root.path);
    final fs = LocalFilesystem(
      pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
    );
    store = HomeClosedWorkspacesStore(
      fs: fs,
      pathOverride: paths.homeWorkspaceClosedWorkspacesJson,
    );
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  const personal =
      LaunchProfileRef(LaunchProfileProvisioner.defaultPersonalId);

  test('recordClosed persists and reloads entries', () async {
    await store.recordClosed(
      const HomeClosedWorkspaceEntry(
        workspaceId: 'proj-a',
        displayName: 'Workspace A',
        primaryPath: '/tmp/a',
        identity: personal,
      ),
    );

    final loaded = await store.load();
    expect(loaded, hasLength(1));
    expect(loaded.first.workspaceId, 'proj-a');
    expect(loaded.first.displayName, 'Workspace A');
    expect(loaded.first.primaryPath, '/tmp/a');
    expect(loaded.first.identity, personal);
    expect(loaded.first.closedAt, greaterThan(0));

    final file = File(
      AppPaths(root.path).homeWorkspaceClosedWorkspacesJson,
    );
    expect(file.existsSync(), isTrue);
  });

  test('recordClosed persists topology snapshot', () async {
    await store.recordClosed(
      const HomeClosedWorkspaceEntry(
        workspaceId: 'proj-a',
        displayName: 'Workspace A',
        primaryPath: '/tmp/a',
        identity: personal,
        topology: WorkspaceTopology.remote,
      ),
    );

    final loaded = await store.load();
    expect(loaded.single.topology, WorkspaceTopology.remote);
  });

  test('remove drops a closed entry by tab key', () async {
    const entryA = HomeClosedWorkspaceEntry(
      workspaceId: 'proj-a',
      displayName: 'A',
      identity: personal,
    );
    const entryB = HomeClosedWorkspaceEntry(
      workspaceId: 'proj-b',
      displayName: 'B',
      identity: personal,
    );
    await store.recordClosed(entryA);
    await store.recordClosed(entryB);

    await store.remove(entryA.tabKey);

    final loaded = await store.load();
    expect(loaded.map((e) => e.workspaceId), ['proj-b']);
  });

  test('load skips entries without launch identity', () async {
    final path = AppPaths(root.path).homeWorkspaceClosedWorkspacesJson;
    await File(path).parent.create(recursive: true);
    await File(path).writeAsString('''
{
  "entries": [
    {"workspaceId": "old", "displayName": "Old"}
  ]
}
''');

    expect(await store.load(), isEmpty);
  });
}
