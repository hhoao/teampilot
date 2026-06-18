import 'dart:convert';

import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Persists open title-bar project tab ids in display order.
class HomeOpenWorkspacesStore {
  HomeOpenWorkspacesStore({Filesystem? fs, String? pathOverride})
      : _fsOverride = fs,
        _pathOverride = pathOverride;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path =>
      _pathOverride ?? AppStorage.paths.homeWorkspaceOpenProjectsJson;

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

  Future<void> saveOrderedIds(List<String> projectIds) async {
    final next = [
      for (final id in projectIds)
        if (id.trim().isNotEmpty) id.trim(),
    ];
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(_path));
    await _fs.atomicWrite(_path, jsonEncode({'projectIds': next}));
  }
}
