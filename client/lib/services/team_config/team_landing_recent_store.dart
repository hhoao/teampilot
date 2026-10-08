import 'dart:convert';

import '../io/filesystem.dart';
import '../storage/home_storage.dart';

/// Persists recently touched team-hub keys at `team-hub/recent.json`.
class TeamLandingRecentStore {
  TeamLandingRecentStore({
    required HomeStorage storage,
    Filesystem? fs,
    String? pathOverride,
  }) : _storage = storage,
       _fsOverride = fs,
       _pathOverride = pathOverride;

  static const maxEntries = 10;

  final HomeStorage _storage;
  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? _storage.fs;
  String get _path => _pathOverride ?? _storage.paths.teamHubRecentJson;

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

  /// Prepends [teamId] to recents, deduping and capping at [maxEntries].
  Future<void> touch(String teamId) async {
    if (teamId.trim().isEmpty) return;
    final existing = await loadOrderedKeys();
    final next = [
      teamId,
      for (final entry in existing)
        if (entry != teamId) entry,
    ].take(maxEntries).toList();
    await _save(next);
  }
}
