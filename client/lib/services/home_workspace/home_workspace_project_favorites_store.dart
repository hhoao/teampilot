import 'dart:convert';

import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Persists favorited project ids at `home-workspace/project-favorites.json`.
class WorkspaceFavoritesStore {
  WorkspaceFavoritesStore({Filesystem? fs, String? pathOverride})
      : _fsOverride = fs,
        _pathOverride = pathOverride;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path =>
      _pathOverride ?? AppStorage.paths.homeWorkspaceProjectFavoritesJson;

  Future<Set<String>> load() async {
    try {
      final text = await _fs.readString(_path);
      if (text == null || text.isEmpty) return <String>{};
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final ids = root['projectIds'];
      if (ids is! List) return <String>{};
      return ids.map((e) => e.toString()).where((s) => s.isNotEmpty).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _save(Set<String> projectIds) async {
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(_path));
    await _fs.atomicWrite(_path, jsonEncode({'projectIds': projectIds.toList()}));
  }

  Future<bool> toggle(String projectId) async {
    final ids = await load();
    final nowOn = !ids.contains(projectId);
    if (nowOn) {
      ids.add(projectId);
    } else {
      ids.remove(projectId);
    }
    await _save(ids);
    return nowOn;
  }
}
