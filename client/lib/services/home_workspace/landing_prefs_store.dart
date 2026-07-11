import 'dart:convert';

import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Per-workspace compose landing preferences.
class LandingPrefs {
  const LandingPrefs({
    this.isPersonal = true,
    this.presetId,
    this.teamId,
    this.projectFolderPath,
    this.expertKey,
    this.workingDirectoryPath,
    this.dangerouslySkipPermissions = false,
  });

  final bool isPersonal;
  final String? presetId;
  final String? teamId;
  final String? projectFolderPath;
  final String? expertKey;
  final String? workingDirectoryPath;
  final bool dangerouslySkipPermissions;

  Map<String, Object?> toJson() => {
    'isPersonal': isPersonal,
    if (presetId != null && presetId!.isNotEmpty) 'presetId': presetId,
    if (teamId != null && teamId!.isNotEmpty) 'teamId': teamId,
    if (projectFolderPath != null && projectFolderPath!.isNotEmpty)
      'projectFolderPath': projectFolderPath,
    if (expertKey != null && expertKey!.isNotEmpty) 'expertKey': expertKey,
    if (workingDirectoryPath != null && workingDirectoryPath!.isNotEmpty)
      'workingDirectoryPath': workingDirectoryPath,
    if (dangerouslySkipPermissions) 'dangerouslySkipPermissions': true,
  };
}

/// Persists landing mode/selection at `ui/workspace-launch-prefs.json`.
class LandingPrefsStore {
  LandingPrefsStore({Filesystem? fs, String? pathOverride})
    : _fsOverride = fs,
      _pathOverride = pathOverride;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path =>
      _pathOverride ?? AppStorage.paths.homeWorkspaceWorkspaceLaunchPrefsJson;

  Future<Map<String, LandingPrefs>> _loadAll() async {
    try {
      final text = await _fs.readString(_path);
      if (text == null || text.isEmpty) return {};
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final out = <String, LandingPrefs>{};
      for (final entry in root.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final m = value.cast<String, Object?>();
        out[entry.key] = LandingPrefs(
          isPersonal: m['isPersonal'] as bool? ?? true,
          presetId: m['presetId'] as String?,
          teamId: m['teamId'] as String?,
          projectFolderPath: m['projectFolderPath'] as String?,
          expertKey: m['expertKey'] as String?,
          workingDirectoryPath: m['workingDirectoryPath'] as String?,
          dangerouslySkipPermissions:
              m['dangerouslySkipPermissions'] as bool? ?? false,
        );
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<LandingPrefs?> prefsFor(String workspaceId) async =>
      (await _loadAll())[workspaceId];

  Future<void> save(String workspaceId, LandingPrefs pref) async {
    final all = await _loadAll();
    all[workspaceId] = pref;
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(_path));
    await _fs.atomicWrite(
      _path,
      jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}),
    );
  }
}
