import 'dart:convert';

import '../../pages/home_workspace/workspace_sort.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';

class WorkspaceDisplayPrefs {
  const WorkspaceDisplayPrefs({
    this.gridView = true,
    this.sort = WorkspaceSort.recentlyUpdated,
  });

  final bool gridView;
  final WorkspaceSort sort;

  WorkspaceDisplayPrefs copyWith({
    bool? gridView,
    WorkspaceSort? sort,
  }) {
    return WorkspaceDisplayPrefs(
      gridView: gridView ?? this.gridView,
      sort: sort ?? this.sort,
    );
  }
}

/// Persists workspace grid/list layout and sort at
/// `home-workspace/workspace-display-prefs.json`.
class WorkspaceDisplayPrefsStore {
  WorkspaceDisplayPrefsStore({Filesystem? fs, String? pathOverride})
    : _fsOverride = fs,
      _pathOverride = pathOverride;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path =>
      _pathOverride ?? AppStorage.paths.homeWorkspaceWorkspaceDisplayPrefsJson;

  Future<WorkspaceDisplayPrefs> load() async {
    try {
      final text = await _fs.readString(_path);
      if (text == null || text.isEmpty) {
        return const WorkspaceDisplayPrefs();
      }
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      return WorkspaceDisplayPrefs(
        gridView: root['gridView'] as bool? ?? true,
        sort: WorkspaceSortLabels.parse(root['sort'] as String?),
      );
    } catch (_) {
      return const WorkspaceDisplayPrefs();
    }
  }

  Future<void> save(WorkspaceDisplayPrefs prefs) async {
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(_path));
    await _fs.atomicWrite(
      _path,
      jsonEncode({'gridView': prefs.gridView, 'sort': prefs.sort.name}),
    );
  }
}
