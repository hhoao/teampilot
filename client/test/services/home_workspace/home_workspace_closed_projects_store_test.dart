import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/home_closed_workspace_entry.dart';
import 'package:teampilot/services/home_workspace/home_workspace_closed_workspaces_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';

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

  test('recordClosed persists and reloads entries', () async {
    await store.recordClosed(
      const HomeClosedWorkspaceEntry(
        workspaceId: 'proj-a',
        displayName: 'Workspace A',
        primaryPath: '/tmp/a',
      ),
    );

    final loaded = await store.load();
    expect(loaded, hasLength(1));
    expect(loaded.first.workspaceId, 'proj-a');
    expect(loaded.first.displayName, 'Workspace A');
    expect(loaded.first.primaryPath, '/tmp/a');
    expect(loaded.first.closedAt, greaterThan(0));

    final file = File(
      AppPaths(root.path).homeWorkspaceClosedWorkspacesJson,
    );
    expect(file.existsSync(), isTrue);
  });

  test('remove drops a closed entry', () async {
    await store.recordClosed(
      const HomeClosedWorkspaceEntry(
        workspaceId: 'proj-a',
        displayName: 'A',
      ),
    );
    await store.recordClosed(
      const HomeClosedWorkspaceEntry(
        workspaceId: 'proj-b',
        displayName: 'B',
      ),
    );

    await store.remove('proj-a');

    final loaded = await store.load();
    expect(loaded.map((e) => e.workspaceId), ['proj-b']);
  });
}
