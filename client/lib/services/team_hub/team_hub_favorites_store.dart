import 'dart:convert';

import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Persists the set of favorited public-team keys at `team-hub/favorites.json`.
class TeamHubFavoritesStore {
  TeamHubFavoritesStore({Filesystem? fs, String? pathOverride})
      : _fsOverride = fs,
        _pathOverride = pathOverride;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path => _pathOverride ?? AppStorage.paths.teamHubFavoritesJson;

  Future<Set<String>> load() async {
    try {
      final text = await _fs.readString(_path);
      if (text == null || text.isEmpty) return <String>{};
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final keys = root['keys'];
      if (keys is! List) return <String>{};
      return keys.map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _save(Set<String> keys) async {
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(_path));
    await _fs.atomicWrite(_path, jsonEncode({'keys': keys.toList()}));
  }

  Future<void> add(String key) async {
    final keys = await load()..add(key);
    await _save(keys);
  }

  Future<void> remove(String key) async {
    final keys = await load()..remove(key);
    await _save(keys);
  }

  /// Flips membership; returns the new state (true = now favorited).
  Future<bool> toggle(String key) async {
    final keys = await load();
    final nowOn = !keys.contains(key);
    if (nowOn) {
      keys.add(key);
    } else {
      keys.remove(key);
    }
    await _save(keys);
    return nowOn;
  }
}
