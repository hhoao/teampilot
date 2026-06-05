import 'dart:convert';

import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Persists recently opened project ids (most recent first).
class HomeWorkspaceRecentProjectsStore {
  HomeWorkspaceRecentProjectsStore({Filesystem? fs, String? pathOverride})
      : _fsOverride = fs,
        _pathOverride = pathOverride;

  static const maxEntries = 30;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path =>
      _pathOverride ?? AppStorage.paths.homeWorkspaceRecentProjectsJson;

  Future<List<String>> loadOrderedIds() async {
    try {
      final text = await _fs.readString(_path);
      if (text == null || text.isEmpty) return [];
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final ids = root['projectIds'];
      if (ids is! List) return [];
      return ids.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> recordVisit(String projectId) async {
    final trimmed = projectId.trim();
    if (trimmed.isEmpty) return;
    final existing = await loadOrderedIds();
    final next = [
      trimmed,
      for (final id in existing)
        if (id != trimmed) id,
    ].take(maxEntries).toList();
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(_path));
    await _fs.atomicWrite(_path, jsonEncode({'projectIds': next}));
  }
}
