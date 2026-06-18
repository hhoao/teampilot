import 'dart:convert';

import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Remembered "open with…" choice for one project.
class ProjectLaunchPref {
  const ProjectLaunchPref({required this.lastIdentity, required this.remember});

  /// Encoded [LaunchIdentity] ("personal" | "team:<id>").
  final String lastIdentity;

  /// When true, opening the project skips the dialog and uses [lastIdentity].
  final bool remember;
}

/// Persists per-project launch choices at
/// `ui/project-launch-prefs.json` as `{ projectId: {...} }`.
class HomeWorkspaceProjectLaunchPrefsStore {
  HomeWorkspaceProjectLaunchPrefsStore({Filesystem? fs, String? pathOverride})
    : _fsOverride = fs,
      _pathOverride = pathOverride;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path =>
      _pathOverride ?? AppStorage.paths.homeWorkspaceProjectLaunchPrefsJson;

  Future<Map<String, ProjectLaunchPref>> _loadAll() async {
    try {
      final text = await _fs.readString(_path);
      if (text == null || text.isEmpty) return {};
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final out = <String, ProjectLaunchPref>{};
      for (final entry in root.entries) {
        final value = entry.value;
        if (value is Map) {
          final m = value.cast<String, Object?>();
          final id = m['lastIdentity'] as String?;
          if (id == null || id.isEmpty) continue;
          out[entry.key] = ProjectLaunchPref(
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

  Future<ProjectLaunchPref?> prefsFor(String projectId) async =>
      (await _loadAll())[projectId];

  Future<void> save(String projectId, ProjectLaunchPref pref) async {
    final all = await _loadAll();
    all[projectId] = pref;
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
