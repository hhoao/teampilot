import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/team_config.dart';
import '../services/app_storage.dart';
import '../services/flashskyai_storage_roots.dart';
import '../services/remote_file_store.dart';

/// Persists [TeamConfig] objects in TeamPilot's own metadata directory.
///
/// - UI dir ([AppStorage.teamsDir]): one `<name>.json` per team, holding the
///   full UI schema (provider, model, agent, extraArgs, prompt, ...).
///
/// CLI-specific files are launch-time artifacts and are generated outside this
/// repository path.
class _TeamPaths {
  const _TeamPaths({required this.teamsUiDir, this.remote});

  final String teamsUiDir;
  final RemoteFileStore? remote;

  bool get uiIsRemote => remote != null;
}

class TeamRepository {
  TeamRepository({String? rootDir, FlashskyaiStorageRoots? storageRoots})
    : _rootDirOverride = rootDir,
      _storageRoots = storageRoots;

  final String? _rootDirOverride;
  final FlashskyaiStorageRoots? _storageRoots;

  String get rootDir => _rootDirOverride ?? AppStorage.teamsDir;

  Future<_TeamPaths> _paths() async {
    if (_storageRoots != null) {
      final snap = await _storageRoots.resolve();
      if (snap.storageIsRemote && snap.remoteFileStore != null) {
        return _TeamPaths(
          teamsUiDir: snap.teamsUiDir,
          remote: snap.remoteFileStore,
        );
      }
    }
    return _TeamPaths(teamsUiDir: _rootDirOverride ?? AppStorage.teamsDir);
  }

  Future<List<TeamConfig>> loadTeams() async {
    final paths = await _paths();
    final teams = List<TeamConfig>.of(
      paths.uiIsRemote
          ? await _readUiDirRemote(paths)
          : await _readUiDir(paths.teamsUiDir),
    );

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
    if (paths.uiIsRemote) {
      await _writeUiDirRemote(paths, stamped);
    } else {
      await _writeUiDir(stamped, paths.teamsUiDir);
    }
  }

  Future<List<TeamConfig>> _readUiDirRemote(_TeamPaths paths) async {
    final store = paths.remote!;
    final posix = p.Context(style: p.Style.posix);
    final teams = <TeamConfig>[];
    try {
      final entries = await store.listDirectoryEntries(paths.teamsUiDir);
      for (final entry in entries) {
        if (entry.isDirectory || !entry.name.endsWith('.json')) continue;
        final content = await store.readFile(
          posix.join(paths.teamsUiDir, entry.name),
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

  Future<void> _writeUiDirRemote(
    _TeamPaths paths,
    List<TeamConfig> teams,
  ) async {
    final store = paths.remote!;
    final posix = p.Context(style: p.Style.posix);
    await store.ensureDirectory(paths.teamsUiDir);
    final keepFiles = <String>{};
    for (final team in teams) {
      final filename = '${team.name}.json';
      keepFiles.add(filename);
      await store.writeFile(
        posix.join(paths.teamsUiDir, filename),
        const JsonEncoder.withIndent('  ').convert(team.toJson()),
      );
    }
    try {
      final entries = await store.listDirectoryEntries(paths.teamsUiDir);
      for (final entry in entries) {
        if (entry.isDirectory) continue;
        if (!entry.name.endsWith('.json')) continue;
        if (keepFiles.contains(entry.name)) continue;
        await store.deleteFile(posix.join(paths.teamsUiDir, entry.name));
      }
    } on Object {
      // best effort
    }
  }

  Future<List<TeamConfig>> _readUiDir(String rootDir) async {
    final dir = Directory(rootDir);
    if (!await dir.exists()) return const [];
    final teams = <TeamConfig>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.json')) continue;
      try {
        final raw = await entity.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        teams.add(TeamConfig.fromJson(Map<String, Object?>.from(decoded)));
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    return teams;
  }

  Future<void> _writeUiDir(List<TeamConfig> teams, String rootDir) async {
    final root = Directory(rootDir);
    await root.create(recursive: true);

    final keepFiles = <String>{};
    for (final team in teams) {
      final filename = '${team.name}.json';
      keepFiles.add(filename);
      final file = File(p.join(root.path, filename));
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(team.toJson()),
      );
    }
    await for (final entity in root.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith('.json')) continue;
      if (keepFiles.contains(name)) continue;
      try {
        await entity.delete();
      } on FileSystemException {
        // best effort
      }
    }
  }

  /// Removes [name] from the UI dir (`<rootDir>/<name>.json`).
  Future<void> deleteTeam(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final paths = await _paths();
    if (paths.uiIsRemote) {
      final store = paths.remote!;
      final posix = p.Context(style: p.Style.posix);
      await store.deleteFile(posix.join(paths.teamsUiDir, '$trimmed.json'));
      return;
    }

    final uiFile = File(p.join(paths.teamsUiDir, '$trimmed.json'));
    if (await uiFile.exists()) {
      try {
        await uiFile.delete();
      } on FileSystemException {
        // best effort
      }
    }
  }
}
