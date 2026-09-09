import 'dart:convert';

import '../io/filesystem.dart';
import '../storage/home_storage.dart';

/// Persists favorited workspace ids at `home-workspace/workspace-favorites.json`.
class WorkspaceFavoritesStore {
  WorkspaceFavoritesStore({
    required HomeStorage storage,
    Filesystem? fs,
    String? pathOverride,
  }) : _storage = storage,
       _fsOverride = fs,
       _pathOverride = pathOverride;

  final HomeStorage _storage;
  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? _storage.fs;
  String get _path =>
      _pathOverride ?? _storage.paths.homeWorkspaceWorkspaceFavoritesJson;

  Future<Set<String>> load() async {
    try {
      final text = await _fs.readString(_path);
      if (text == null || text.isEmpty) return <String>{};
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final ids = root['workspaceIds'];
      if (ids is! List) return <String>{};
      return ids.map((e) => e.toString()).where((s) => s.isNotEmpty).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _save(Set<String> workspaceIds) async {
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(_path));
    await _fs.atomicWrite(
      _path,
      jsonEncode({'workspaceIds': workspaceIds.toList()}),
    );
  }

  Future<bool> toggle(String workspaceId) async {
    final ids = await load();
    final nowOn = !ids.contains(workspaceId);
    if (nowOn) {
      ids.add(workspaceId);
    } else {
      ids.remove(workspaceId);
    }
    await _save(ids);
    return nowOn;
  }
}
