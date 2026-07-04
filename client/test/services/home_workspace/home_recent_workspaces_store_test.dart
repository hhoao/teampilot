import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_tab_ref.dart';
import 'package:teampilot/services/home_workspace/home_recent_workspaces_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';

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

  test('recordVisit dedupes by workspace id', () async {
    const tabA = WorkspaceTabRef(workspaceId: 'proj-a');
    const tabB = WorkspaceTabRef(workspaceId: 'proj-b');

    await store.recordVisit(tabA);
    await store.recordVisit(tabB);

    expect(await store.loadOrderedTabs(), [tabB, tabA]);
  });

  test('recordVisit moves existing workspace id to front', () async {
    const tabA = WorkspaceTabRef(workspaceId: 'proj-a');
    const tabB = WorkspaceTabRef(workspaceId: 'proj-b');

    await store.recordVisit(tabA);
    await store.recordVisit(tabB);
    await store.recordVisit(tabA);

    expect(await store.loadOrderedTabs(), [tabA, tabB]);
  });

  test('loadOrderedTabs ignores legacy workspaceIds payload', () async {
    final path = AppPaths(root.path).homeWorkspaceRecentWorkspacesJson;
    await File(path).parent.create(recursive: true);
    await File(path).writeAsString('{"workspaceIds":["proj-a","proj-b"]}');

    expect(await store.loadOrderedTabs(), isEmpty);
  });
}
