import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_project_sort.dart';
import 'package:teampilot/services/home_workspace/home_workspace_project_display_prefs_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  late Directory root;
  late HomeWorkspaceProjectDisplayPrefsStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('project_display_prefs_');
    final paths = AppPaths(root.path);
    final fs = LocalFilesystem(
      pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
    );
    store = HomeWorkspaceProjectDisplayPrefsStore(
      fs: fs,
      pathOverride: paths.homeWorkspaceProjectDisplayPrefsJson,
    );
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test('load returns defaults when file is missing', () async {
    final prefs = await store.load();
    expect(prefs.gridView, isTrue);
    expect(prefs.sort, HomeWorkspaceProjectSort.recentlyUpdated);
  });

  test('save persists grid view and sort mode', () async {
    await store.save(
      const HomeWorkspaceProjectDisplayPrefs(
        gridView: false,
        sort: HomeWorkspaceProjectSort.nameAsc,
      ),
    );

    final prefs = await store.load();
    expect(prefs.gridView, isFalse);
    expect(prefs.sort, HomeWorkspaceProjectSort.nameAsc);

    final file = File(AppPaths(root.path).homeWorkspaceProjectDisplayPrefsJson);
    expect(file.existsSync(), isTrue);
  });
}
