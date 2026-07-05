import 'dart:convert';

import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Persists recently touched member-hub keys at `member-hub/recent.json`.
class ExpertHubRecentStore {
  ExpertHubRecentStore({Filesystem? fs, String? pathOverride})
    : _fsOverride = fs,
      _pathOverride = pathOverride;

  static const maxEntries = 10;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path => _pathOverride ?? AppStorage.paths.memberHubRecentJson;

  Future<List<String>> loadOrderedKeys() async {
    try {
      final text = await _fs.readString(_path);
      if (text == null || text.isEmpty) return [];
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final keysRaw = root['keys'];
      if (keysRaw is! List) return [];
      return keysRaw.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<String> keys) async {
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(_path));
    await _fs.atomicWrite(_path, jsonEncode({'keys': keys}));
  }

  /// Prepends [key] to recents, deduping and capping at [maxEntries].
  Future<void> touch(String key) async {
    if (key.trim().isEmpty) return;
    final existing = await loadOrderedKeys();
    final next = [
      key,
      for (final entry in existing)
        if (entry != key) entry,
    ].take(maxEntries).toList();
    await _save(next);
  }
}
