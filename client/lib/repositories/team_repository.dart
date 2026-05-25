import 'dart:convert';

import '../models/team_config.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/flashskyai_storage_roots.dart';
import '../services/io/filesystem.dart';
import '../services/session/session_lifecycle_service.dart';

/// Persists [TeamConfig] objects in TeamPilot's own metadata directory.
///
/// - UI dir ([AppStorage.teamsDir]): one `<name>.json` per team, holding the
///   full UI schema (provider, model, agent, extraArgs, prompt, ...).
///
/// CLI-specific files are launch-time artifacts and are generated outside this
/// repository path.
class _TeamPaths {
  _TeamPaths({required this.teamsUiDir, Filesystem? fs})
    : fs = fs ?? AppStorage.fs;

  final String teamsUiDir;
  final Filesystem fs;
}

class TeamRepository {
  TeamRepository({
    String? rootDir,
    FlashskyaiStorageRoots? storageRoots,
    SessionLifecycleService? lifecycleService,
  }) : _rootDirOverride = rootDir,
       _storageRoots = storageRoots,
       _lifecycleService = lifecycleService;

  final String? _rootDirOverride;
  final FlashskyaiStorageRoots? _storageRoots;
  final SessionLifecycleService? _lifecycleService;

  String get rootDir =>
      _rootDirOverride ?? AppStorage.paths.teamsDir;

  Future<_TeamPaths> _paths() async {
    if (_storageRoots != null) {
      final snap = await _storageRoots.resolve();
      return _TeamPaths(teamsUiDir: snap.teamsUiDir, fs: snap.fs);
    }
    return _TeamPaths(
      teamsUiDir: _rootDirOverride ?? AppPathsBootstrapper.current.teamsDir,
    );
  }

  Future<List<TeamConfig>> loadTeams() async {
    final paths = await _paths();
    final teams = List<TeamConfig>.of(await _readUiDir(paths));

    teams.sort((a, b) {
      if (a.createdAt != b.createdAt) {
        return a.createdAt.compareTo(b.createdAt);
      }
      return a.name.compareTo(b.name);
    });
    return List.unmodifiable(teams);
  }

  Future<void> saveTeams(List<TeamConfig> teams) async {
    final stamped = <TeamConfig>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final team in teams) {
      final name = team.name.trim();
      if (name.isEmpty) continue;
      stamped.add(team.createdAt > 0 ? team : team.copyWith(createdAt: now));
    }
    final paths = await _paths();
    await _writeUiDir(paths, stamped);
  }

  Future<List<TeamConfig>> _readUiDir(_TeamPaths paths) async {
    final teams = <TeamConfig>[];
    try {
      final entries = await paths.fs.listDir(paths.teamsUiDir);
      for (final entry in entries) {
        if (entry.isDirectory || !entry.name.endsWith('.json')) continue;
        final content = await paths.fs.readString(
          paths.fs.pathContext.join(paths.teamsUiDir, entry.name),
        );
        if (content == null || content.isEmpty) continue;
        try {
          final decoded = jsonDecode(content);
          if (decoded is! Map) continue;
          teams.add(TeamConfig.fromJson(Map<String, Object?>.from(decoded)));
        } on FormatException {
          continue;
        }
      }
    } on Object {
      return const [];
    }
    return teams;
  }

  Future<void> _writeUiDir(_TeamPaths paths, List<TeamConfig> teams) async {
    await paths.fs.ensureDir(paths.teamsUiDir);
    final keepFiles = <String>{};
    for (final team in teams) {
      final filename = '${team.name}.json';
      keepFiles.add(filename);
      await paths.fs.atomicWrite(
        paths.fs.pathContext.join(paths.teamsUiDir, filename),
        const JsonEncoder.withIndent('  ').convert(team.toJson()),
      );
    }
    try {
      final entries = await paths.fs.listDir(paths.teamsUiDir);
      for (final entry in entries) {
        if (entry.isDirectory) continue;
        if (!entry.name.endsWith('.json')) continue;
        if (keepFiles.contains(entry.name)) continue;
        await paths.fs.removeRecursive(
          paths.fs.pathContext.join(paths.teamsUiDir, entry.name),
        );
      }
    } on Object {
      // best effort
    }
  }

  /// Removes [name] from the UI dir (`<rootDir>/<name>.json`).
  Future<void> deleteTeam(
    String name, {
    bool destroyCliState = true,
    String? cliStateTeamId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    if (destroyCliState) {
      final cleanupTeamId = cliStateTeamId?.trim();
      await _lifecycleService?.destroyTeamCliState(
        cleanupTeamId != null && cleanupTeamId.isNotEmpty
            ? cleanupTeamId
            : trimmed,
      );
    }

    final paths = await _paths();
    try {
      await paths.fs.removeRecursive(
        paths.fs.pathContext.join(paths.teamsUiDir, '$trimmed.json'),
      );
    } on Object {
      // best effort
    }
  }
}
