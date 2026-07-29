import 'dart:convert';

import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Persists per-workspace Run UI prefs at `ui/run-ui-prefs.json`.
class RunUiPrefsStore {
  RunUiPrefsStore({Filesystem? fs, String? pathOverride})
    : _fsOverride = fs,
      _pathOverride = pathOverride;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path => _pathOverride ?? AppStorage.paths.runUiPrefsJson;

  Future<Map<String, String?>> _loadAll() async {
    try {
      final text = await _fs.readString(_path);
      if (text == null || text.isEmpty) return {};
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final out = <String, String?>{};
      for (final entry in root.entries) {
        final value = entry.value;
        if (value is Map) {
          final m = value.cast<String, Object?>();
          out[entry.key] = m['selectedKey'] as String?;
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<String?> selectedKeyFor(String workspaceId) async =>
      (await _loadAll())[workspaceId];

  Future<void> saveSelectedKey(String workspaceId, String selectedKey) async {
    final all = await _loadAll();
    all[workspaceId] = selectedKey;
    await _writeAll(all);
  }

  Future<void> clearSelectedKey(String workspaceId) async {
    final all = await _loadAll();
    all.remove(workspaceId);
    await _writeAll(all);
  }

  Future<void> _writeAll(Map<String, String?> all) async {
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(_path));
    await _fs.atomicWrite(
      _path,
      jsonEncode({
        for (final e in all.entries)
          e.key: {'selectedKey': e.value},
      }),
    );
  }
}
