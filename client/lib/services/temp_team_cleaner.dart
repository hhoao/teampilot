import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_storage.dart';

/// Tracks the temp team folders the UI causes the CLI to create under
/// `~/.flashskyai/teams/<sessionTeamName>` and removes them on demand.
///
/// The registry is persisted to disk so a crashed run can still be cleaned
/// up the next time the UI starts.
class TempTeamCleaner {
  TempTeamCleaner({String? registryPath, String? cliTeamsDir})
      : _registryPathOverride = registryPath,
        _cliTeamsDirOverride = cliTeamsDir;

  final String? _registryPathOverride;
  final String? _cliTeamsDirOverride;

  String get registryPath =>
      _registryPathOverride ??
      p.join(AppStorage.flashskyaiDir, 'ui-temp-teams.json');

  String get cliTeamsDir =>
      _cliTeamsDirOverride ??
      p.join(
        Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '.',
        '.flashskyai',
        'teams',
      );

  /// Records [name] as a UI-created temp team. Persists immediately so it
  /// survives a crash.
  Future<void> record(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final names = await _loadRegistry();
    if (!names.add(trimmed)) return;
    await _writeRegistry(names);
  }

  /// Deletes every recorded temp team directory under [cliTeamsDir].
  /// Names whose directories could not be deleted are kept in the registry
  /// so the next [cleanup] will retry them.
  Future<void> cleanup() async {
    final names = await _loadRegistry();
    if (names.isEmpty) return;

    final failed = <String>{};
    for (final name in names) {
      final dir = Directory(p.join(cliTeamsDir, name));
      if (!await dir.exists()) continue;
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        failed.add(name);
      }
    }

    // Only remove successful names from the registry. Failed ones stay so
    // they will be retried on the next run.
    final remaining = names
        .where((n) => failed.contains(n) || Directory(p.join(cliTeamsDir, n)).existsSync())
        .toSet();
    if (remaining.isEmpty) {
      await _clearRegistry();
    } else {
      await _writeRegistry(remaining);
    }
  }

  Future<Set<String>> _loadRegistry() async {
    final file = File(registryPath);
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
    final file = File(registryPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(names.toList()));
  }

  Future<void> _clearRegistry() async {
    final file = File(registryPath);
    if (await file.exists()) {
      try {
        await file.delete();
      } on FileSystemException {
        // best effort
      }
    }
  }
}
