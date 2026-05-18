import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_storage.dart';
import 'flashskyai_storage_roots.dart';
import 'remote_file_store.dart';

/// Tracks the temp team folders the UI causes the CLI to create under
/// `~/.flashskyai/teams/<sessionTeamName>` and removes them on demand.
class TempTeamCleaner {
  TempTeamCleaner({
    String? registryPath,
    String? cliTeamsDir,
    FlashskyaiStorageRoots? storageRoots,
  }) : _registryPathOverride = registryPath,
       _cliTeamsDirOverride = cliTeamsDir,
       _storageRoots = storageRoots;

  final String? _registryPathOverride;
  final String? _cliTeamsDirOverride;
  final FlashskyaiStorageRoots? _storageRoots;

  Future<_CleanerPaths> _paths() async {
    if (_storageRoots != null) {
      final snap = await _storageRoots.resolve();
      return _CleanerPaths(
        registryPath: snap.tempTeamRegistryPath,
        cliTeamsDir: snap.cliTeamsDir,
        remote: snap.remoteFileStore,
      );
    }
    return _CleanerPaths(
      registryPath: _registryPathOverride ?? AppStorage.tempTeamRegistryPath,
      cliTeamsDir: _cliTeamsDirOverride ?? AppStorage.cliTeamsDir,
    );
  }

  Future<void> record(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final names = await _loadRegistry();
    if (!names.add(trimmed)) return;
    await _writeRegistry(names);
  }

  Future<void> cleanup() async {
    final paths = await _paths();
    final names = await _loadRegistry();
    if (names.isEmpty) return;

    final failed = <String>{};
    for (final name in names) {
      final teamDir = p.join(paths.cliTeamsDir, name);
      if (paths.remote != null) {
        final configPath = p.Context(
          style: p.Style.posix,
        ).join(teamDir, 'config.json');
        if (!await paths.remote!.fileExists(configPath)) continue;
        try {
          await paths.remote!.removeRecursive(teamDir);
        } on Object {
          failed.add(name);
        }
        continue;
      }

      final dir = Directory(teamDir);
      if (!await dir.exists()) continue;
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        failed.add(name);
      }
    }

    final remaining = <String>{};
    for (final name in names) {
      if (failed.contains(name)) {
        remaining.add(name);
        continue;
      }
      if (paths.remote != null) {
        final configPath = p.Context(
          style: p.Style.posix,
        ).join(paths.cliTeamsDir, name, 'config.json');
        if (await paths.remote!.fileExists(configPath)) {
          remaining.add(name);
        }
      } else if (Directory(p.join(paths.cliTeamsDir, name)).existsSync()) {
        remaining.add(name);
      }
    }

    if (remaining.isEmpty) {
      await _clearRegistry();
    } else {
      await _writeRegistry(remaining);
    }
  }

  Future<Set<String>> _loadRegistry() async {
    final paths = await _paths();
    if (paths.remote != null) {
      final raw = await paths.remote!.readFile(paths.registryPath);
      if (raw == null || raw.trim().isEmpty) return <String>{};
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.whereType<String>().toSet();
        }
      } on FormatException {
        return <String>{};
      }
      return <String>{};
    }

    final file = File(paths.registryPath);
    if (!await file.exists()) return <String>{};
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <String>{};
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toSet();
      }
    } on FormatException {
      return <String>{};
    } on FileSystemException {
      return <String>{};
    }
    return <String>{};
  }

  Future<void> _writeRegistry(Set<String> names) async {
    final paths = await _paths();
    final text = jsonEncode(names.toList());
    if (paths.remote != null) {
      final posix = p.Context(style: p.Style.posix);
      final parent = posix.dirname(paths.registryPath);
      if (parent.isNotEmpty && parent != '.') {
        await paths.remote!.ensureDirectory(parent);
      }
      await paths.remote!.writeFile(paths.registryPath, text);
      return;
    }
    final file = File(paths.registryPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  Future<void> _clearRegistry() async {
    final paths = await _paths();
    if (paths.remote != null) {
      try {
        await paths.remote!.deleteFile(paths.registryPath);
      } on Object {
        // best effort
      }
      return;
    }
    final file = File(paths.registryPath);
    if (await file.exists()) {
      try {
        await file.delete();
      } on FileSystemException {
        // best effort
      }
    }
  }
}

class _CleanerPaths {
  const _CleanerPaths({
    required this.registryPath,
    required this.cliTeamsDir,
    this.remote,
  });

  final String registryPath;
  final String cliTeamsDir;
  final RemoteFileStore? remote;
}
