import 'dart:convert';

import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Remembered "open with…" choice for one workspace.
class WorkspaceLaunchPref {
  const WorkspaceLaunchPref({required this.lastIdentity, required this.remember});

  /// Encoded launch identity: `personal` or `team:ID`.
  final String lastIdentity;

  /// When true, opening the workspace skips the dialog and uses [lastIdentity].
  final bool remember;
}

/// Persists per-workspace launch choices at
/// `ui/workspace-launch-prefs.json` as `{ workspaceId: {...} }`.
class WorkspaceLaunchPrefsStore {
  WorkspaceLaunchPrefsStore({Filesystem? fs, String? pathOverride})
    : _fsOverride = fs,
      _pathOverride = pathOverride;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path =>
      _pathOverride ?? AppStorage.paths.homeWorkspaceWorkspaceLaunchPrefsJson;

  Future<Map<String, WorkspaceLaunchPref>> _loadAll() async {
    try {
      final text = await _fs.readString(_path);
      if (text == null || text.isEmpty) return {};
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final out = <String, WorkspaceLaunchPref>{};
      for (final entry in root.entries) {
        final value = entry.value;
        if (value is Map) {
          final m = value.cast<String, Object?>();
          final id = m['lastIdentity'] as String?;
          if (id == null || id.isEmpty) continue;
          out[entry.key] = WorkspaceLaunchPref(
            lastIdentity: id,
            remember: m['remember'] as bool? ?? false,
          );
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<WorkspaceLaunchPref?> prefsFor(String workspaceId) async =>
      (await _loadAll())[workspaceId];

  Future<void> save(String workspaceId, WorkspaceLaunchPref pref) async {
    final all = await _loadAll();
    all[workspaceId] = pref;
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(_path));
    await _fs.atomicWrite(
      _path,
      jsonEncode({
        for (final e in all.entries)
          e.key: {
            'lastIdentity': e.value.lastIdentity,
            'remember': e.value.remember,
          },
      }),
    );
  }
}
