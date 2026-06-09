import 'dart:convert';

import '../../pages/home_workspace/home_workspace_project_sort.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';

class HomeWorkspaceProjectDisplayPrefs {
  const HomeWorkspaceProjectDisplayPrefs({
    this.gridView = true,
    this.sort = HomeWorkspaceProjectSort.recentlyUpdated,
  });

  final bool gridView;
  final HomeWorkspaceProjectSort sort;

  HomeWorkspaceProjectDisplayPrefs copyWith({
    bool? gridView,
    HomeWorkspaceProjectSort? sort,
  }) {
    return HomeWorkspaceProjectDisplayPrefs(
      gridView: gridView ?? this.gridView,
      sort: sort ?? this.sort,
    );
  }
}

/// Persists project grid/list layout and sort at
/// `home-workspace/project-display-prefs.json`.
class HomeWorkspaceProjectDisplayPrefsStore {
  HomeWorkspaceProjectDisplayPrefsStore({Filesystem? fs, String? pathOverride})
    : _fsOverride = fs,
      _pathOverride = pathOverride;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path =>
      _pathOverride ?? AppStorage.paths.homeWorkspaceProjectDisplayPrefsJson;

  Future<HomeWorkspaceProjectDisplayPrefs> load() async {
    try {
      final text = await _fs.readString(_path);
      if (text == null || text.isEmpty) {
        return const HomeWorkspaceProjectDisplayPrefs();
      }
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      return HomeWorkspaceProjectDisplayPrefs(
        gridView: root['gridView'] as bool? ?? true,
        sort: HomeWorkspaceProjectSortLabels.parse(root['sort'] as String?),
      );
    } catch (_) {
      return const HomeWorkspaceProjectDisplayPrefs();
    }
  }

  Future<void> save(HomeWorkspaceProjectDisplayPrefs prefs) async {
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(_path));
    await _fs.atomicWrite(
      _path,
      jsonEncode({'gridView': prefs.gridView, 'sort': prefs.sort.name}),
    );
  }
}
