import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/home_closed_project_entry.dart';
import 'package:teampilot/services/home_workspace/home_workspace_closed_projects_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  late Directory root;
  late HomeWorkspaceClosedProjectsStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('closed_projects_store_');
    final paths = AppPaths(root.path);
    final fs = LocalFilesystem(
      pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
    );
    store = HomeWorkspaceClosedProjectsStore(
      fs: fs,
      pathOverride: paths.homeWorkspaceClosedProjectsJson,
    );
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test('recordClosed persists and reloads entries', () async {
    await store.recordClosed(
      const HomeClosedProjectEntry(
        projectId: 'proj-a',
        displayName: 'Project A',
        primaryPath: '/tmp/a',
      ),
    );

    final loaded = await store.load();
    expect(loaded, hasLength(1));
    expect(loaded.first.projectId, 'proj-a');
    expect(loaded.first.displayName, 'Project A');
    expect(loaded.first.primaryPath, '/tmp/a');
    expect(loaded.first.closedAt, greaterThan(0));

    final file = File(
      AppPaths(root.path).homeWorkspaceClosedProjectsJson,
    );
    expect(file.existsSync(), isTrue);
  });

  test('remove drops a closed entry', () async {
    await store.recordClosed(
      const HomeClosedProjectEntry(
        projectId: 'proj-a',
        displayName: 'A',
      ),
    );
    await store.recordClosed(
      const HomeClosedProjectEntry(
        projectId: 'proj-b',
        displayName: 'B',
      ),
    );

    await store.remove('proj-a');

    final loaded = await store.load();
    expect(loaded.map((e) => e.projectId), ['proj-b']);
  });
}
