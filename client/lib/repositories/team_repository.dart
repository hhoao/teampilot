import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/team_config.dart';
import '../services/app_storage.dart';

/// Persists [TeamConfig] objects under [AppStorage.teamsDir] as one JSON file
/// per team: `<teamsDir>/<name>.json`.
class TeamRepository {
  TeamRepository({String? rootDir, String? cliTeamsDir})
      : _rootDirOverride = rootDir,
        _cliTeamsDirOverride = cliTeamsDir;

  final String? _rootDirOverride;
  final String? _cliTeamsDirOverride;

  String get rootDir => _rootDirOverride ?? AppStorage.teamsDir;

  /// The `~/.flashskyai/teams` directory managed by the CLI.
  String get cliTeamsDir => _cliTeamsDirOverride ?? p.join(
        Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '.',
        '.flashskyai',
        'teams',
      );

  /// Import teams from [cliTeamsDir] that are not already present in
  /// [rootDir].  Idempotent — running it twice won't produce duplicates.
  Future<int> importFromCli() async {
    final src = Directory(cliTeamsDir);
    if (!await src.exists()) return 0;

    final existing = await loadTeams();
    final byName = {for (final t in existing) t.name};

    final incoming = <TeamConfig>[];
    await for (final entity in src.list()) {
      if (entity is! Directory) continue;
      final configFile = File(p.join(entity.path, 'config.json'));
      if (!await configFile.exists()) continue;
      try {
        final raw = await configFile.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final team = _cliJsonToTeam(Map<String, Object?>.from(decoded));
        if (team == null || byName.contains(team.name)) continue;
        incoming.add(team);
        byName.add(team.name);
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
    }

    if (incoming.isEmpty) return 0;

    final merged = [...existing, ...incoming];
    await saveTeams(merged);
    return incoming.length;
  }

  TeamConfig? _cliJsonToTeam(Map<String, Object?> json) {
    final name = (json['name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;

    final createdAt = (json['createdAt'] as num?)?.toInt() ?? 0;

    final rawMembers = json['members'];

    final members = <TeamMemberConfig>[];
    if (rawMembers is List) {
      for (final m in rawMembers) {
        if (m is! Map) continue;
        final map = Map<String, Object?>.from(m);
        final member = _cliJsonToMember(map);
        if (member.name.isEmpty) continue;
        members.add(member);
      }
    }

    return TeamConfig(
      id: name,
      name: name,
      members: members,
      createdAt: createdAt,
      loop: TeamConfig.decodeLoop(json['loop']),
    );
  }

  TeamMemberConfig _cliJsonToMember(Map<String, Object?> json) {
    final name = json['name'] as String? ?? '';
    return TeamMemberConfig(
      id: name,
      name: name,
      joinedAt: (json['joinedAt'] as num?)?.toInt() ?? 0,
      dangerouslySkipPermissions:
          TeamMemberConfig.decodeDangerouslySkipPermissions(
        json['dangerouslySkipPermissions'],
      ),
    );
  }

  Future<List<TeamConfig>> loadTeams() async {
    final dir = Directory(rootDir);
    if (!await dir.exists()) {
      return const [];
    }

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

    teams.sort((a, b) {
      if (a.createdAt != b.createdAt) {
        return a.createdAt.compareTo(b.createdAt);
      }
      return a.name.compareTo(b.name);
    });
    return List.unmodifiable(teams);
  }

  Future<void> saveTeams(List<TeamConfig> teams) async {
    final root = Directory(rootDir);
    await root.create(recursive: true);

    final keepFiles = <String>{};
    for (final team in teams) {
      final name = team.name.trim();
      if (name.isEmpty) continue;
      final filename = '$name.json';
      keepFiles.add(filename);
      final stamped = team.createdAt > 0
          ? team
          : team.copyWith(
              createdAt: DateTime.now().millisecondsSinceEpoch,
            );
      final file = File(p.join(root.path, filename));
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(stamped.toJson()),
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
}
