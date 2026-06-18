import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/home_workspace/home_workspace_open_workspaces_store.dart';
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

  test('saveOrderedIds persists tab order', () async {
    await store.saveOrderedIds(['proj-a', 'proj-b']);

    expect(await store.loadOrderedIds(), ['proj-a', 'proj-b']);

    final file = File(AppPaths(root.path).homeWorkspaceOpenWorkspacesJson);
    expect(file.existsSync(), isTrue);
  });
}
