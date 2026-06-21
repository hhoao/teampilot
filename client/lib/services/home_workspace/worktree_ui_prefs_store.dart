import 'dart:convert';

import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Per-workspace worktree sidebar UI state: which groups are collapsed and the
/// last current worktree path.
class WorktreeUiPref {
  const WorktreeUiPref({this.collapsed = const {}, this.currentPath = ''});

  final Set<String> collapsed;
  final String currentPath;
}

/// Persists [WorktreeUiPref] keyed by workspace id at
/// `ui/worktree-ui-prefs.json` as `{ workspaceId: {...} }`. Mirrors
/// [WorkspaceLaunchPrefsStore].
class WorktreeUiPrefsStore {
  WorktreeUiPrefsStore({Filesystem? fs, String? pathOverride})
      : _fsOverride = fs,
        _pathOverride = pathOverride;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path => _pathOverride ?? AppStorage.paths.worktreeUiPrefsJson;

  Future<Map<String, WorktreeUiPref>> _loadAll() async {
    try {
      final text = await _fs.readString(_path);
      if (text == null || text.isEmpty) return {};
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final out = <String, WorktreeUiPref>{};
      for (final entry in root.entries) {
        final value = entry.value;
        if (value is Map) {
          final m = value.cast<String, Object?>();
          final collapsed = (m['collapsed'] as List?)
                  ?.whereType<String>()
                  .toSet() ??
              const <String>{};
          out[entry.key] = WorktreeUiPref(
            collapsed: collapsed,
            currentPath: m['currentPath'] as String? ?? '',
          );
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<WorktreeUiPref?> prefsFor(String workspaceId) async =>
      (await _loadAll())[workspaceId];

  Future<void> save(String workspaceId, WorktreeUiPref pref) async {
    final all = await _loadAll();
    all[workspaceId] = pref;
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(_path));
    await _fs.atomicWrite(
      _path,
      jsonEncode({
        for (final e in all.entries)
          e.key: {
            'collapsed': e.value.collapsed.toList(),
            'currentPath': e.value.currentPath,
          },
      }),
    );
  }
}
