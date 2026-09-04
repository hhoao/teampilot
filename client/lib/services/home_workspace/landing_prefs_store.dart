import 'dart:convert';

import '../../models/team_config.dart';
import '../../models/launch_security_policy.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Per-workspace compose landing preferences.
class LandingPrefs {
  const LandingPrefs({
    this.isPersonal = true,
    this.generateLaunch = false,
    this.presetId,
    this.teamId,
    this.projectFolderPath,
    this.expertKey,
    this.workingDirectoryPath,
    this.launchSecurityPolicy = LaunchSecurityPolicy.fullAccess,
    this.cli,
    this.provider,
    this.model,
    this.effort,
  });

  final bool isPersonal;

  /// True when the landing submit enters the AI team-generation flow.
  final bool generateLaunch;

  final String? presetId;
  final String? teamId;
  final String? projectFolderPath;
  final String? expertKey;
  final String? workingDirectoryPath;
  final LaunchSecurityPolicy launchSecurityPolicy;
  final CliTool? cli;
  final String? provider;
  final String? model;
  final String? effort;

  Map<String, Object?> toJson() => {
    'isPersonal': isPersonal,
    if (generateLaunch) 'generateLaunch': generateLaunch,
    if (presetId != null && presetId!.isNotEmpty) 'presetId': presetId,
    if (teamId != null && teamId!.isNotEmpty) 'teamId': teamId,
    if (projectFolderPath != null && projectFolderPath!.isNotEmpty)
      'projectFolderPath': projectFolderPath,
    if (expertKey != null && expertKey!.isNotEmpty) 'expertKey': expertKey,
    if (workingDirectoryPath != null && workingDirectoryPath!.isNotEmpty)
      'workingDirectoryPath': workingDirectoryPath,
    'launchSecurityPolicy': launchSecurityPolicy.toJson(),
    if (cli != null) 'cli': cli!.value,
    if (provider != null && provider!.isNotEmpty) 'provider': provider,
    if (model != null && model!.isNotEmpty) 'model': model,
    if (effort != null && effort!.isNotEmpty) 'effort': effort,
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
          generateLaunch: m['generateLaunch'] as bool? ?? false,
          presetId: m['presetId'] as String?,
          teamId: m['teamId'] as String?,
          projectFolderPath: m['projectFolderPath'] as String?,
          expertKey: m['expertKey'] as String?,
          workingDirectoryPath: m['workingDirectoryPath'] as String?,
          launchSecurityPolicy: LaunchSecurityPolicy.fromJson(
            m['launchSecurityPolicy'],
          ),
          cli: m['cli'] != null ? CliTool.parse(m['cli']) : null,
          provider: m['provider'] as String?,
          model: m['model'] as String?,
          effort: m['effort'] as String?,
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
