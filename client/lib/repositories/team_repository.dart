import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/team_config.dart';
import '../services/app_storage.dart';

/// Persists [TeamConfig] objects across two locations and merges them on read.
///
/// - UI dir ([AppStorage.teamsDir]): one `<name>.json` per team, holding the
///   full UI schema (provider, model, agent, extraArgs, prompt, ...).
/// - CLI dir ([AppStorage.cliTeamsDir]): one `<name>/config.json` per team,
///   holding the subset shared with the `flashskyai` CLI (name, createdAt,
///   loop, plus per-member name/joinedAt/dangerouslySkipPermissions).
///
/// On load, the two dirs are unioned by team name. For names present in both,
/// CLI wins on the fields it knows about; UI-only fields survive untouched.
/// On save, the full schema is written to the UI dir and the CLI subset is
/// read-modify-written back to the CLI dir so the CLI's own extras (agentId,
/// sessionId, cwd, isActive, leadAgentId, ...) are preserved.
class TeamRepository {
  TeamRepository({String? rootDir, String? cliTeamsDir})
      : _rootDirOverride = rootDir,
        _cliTeamsDirOverride = cliTeamsDir;

  final String? _rootDirOverride;
  final String? _cliTeamsDirOverride;

  String get rootDir => _rootDirOverride ?? AppStorage.teamsDir;

  /// The `~/.flashskyai/teams` directory managed by the CLI.
  String get cliTeamsDir => _cliTeamsDirOverride ?? AppStorage.cliTeamsDir;

  Future<List<TeamConfig>> loadTeams() async {
    final uiTeams = await _readUiDir();
    final cliTeams = await _readCliDir();

    final uiByName = {for (final t in uiTeams) t.name: t};
    final cliByName = {for (final t in cliTeams) t.name: t};

    final names = <String>{...uiByName.keys, ...cliByName.keys};
    final merged = <TeamConfig>[];
    for (final name in names) {
      final ui = uiByName[name];
      final cli = cliByName[name];
      if (ui != null && cli != null) {
        merged.add(_mergeTeam(ui: ui, cli: cli));
      } else {
        merged.add((ui ?? cli)!);
      }
    }

    merged.sort((a, b) {
      if (a.createdAt != b.createdAt) {
        return a.createdAt.compareTo(b.createdAt);
      }
      return a.name.compareTo(b.name);
    });
    return List.unmodifiable(merged);
  }

  Future<void> saveTeams(List<TeamConfig> teams) async {
    final stamped = <TeamConfig>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final team in teams) {
      final name = team.name.trim();
      if (name.isEmpty) continue;
      stamped.add(
        team.createdAt > 0 ? team : team.copyWith(createdAt: now),
      );
    }
    await _writeUiDir(stamped);
    await _syncToCliDir(stamped);
  }

  Future<List<TeamConfig>> _readUiDir() async {
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

  Future<List<TeamConfig>> _readCliDir() async {
    final dir = Directory(cliTeamsDir);
    if (!await dir.exists()) return const [];
    final teams = <TeamConfig>[];
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      final configFile = File(p.join(entity.path, 'config.json'));
      if (!await configFile.exists()) continue;
      try {
        final raw = await configFile.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final team = _cliJsonToTeam(Map<String, Object?>.from(decoded));
        if (team != null) teams.add(team);
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    return teams;
  }

  TeamConfig _mergeTeam({required TeamConfig ui, required TeamConfig cli}) {
    return ui.copyWith(
      name: cli.name,
      createdAt: cli.createdAt,
      loop: cli.loop,
      updateLoop: true,
      members: _mergeMembers(uiMembers: ui.members, cliMembers: cli.members),
    );
  }

  List<TeamMemberConfig> _mergeMembers({
    required List<TeamMemberConfig> uiMembers,
    required List<TeamMemberConfig> cliMembers,
  }) {
    final uiByName = {for (final m in uiMembers) m.name: m};
    final cliNames = cliMembers.map((m) => m.name).toSet();

    final merged = <TeamMemberConfig>[];
    // CLI order first — CLI owns the canonical member ordering.
    for (final cli in cliMembers) {
      final ui = uiByName[cli.name];
      if (ui != null) {
        merged.add(ui.copyWith(
          name: cli.name,
          joinedAt: cli.joinedAt,
          dangerouslySkipPermissions: cli.dangerouslySkipPermissions,
        ));
      } else {
        merged.add(cli);
      }
    }
    // UI-only members (just added in UI, not yet synced to CLI) at the end.
    for (final ui in uiMembers) {
      if (!cliNames.contains(ui.name)) merged.add(ui);
    }
    return merged;
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
        final member = _cliJsonToMember(Map<String, Object?>.from(m));
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

  Future<void> _writeUiDir(List<TeamConfig> teams) async {
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

  /// Writes the CLI subset back to `<cliTeamsDir>/<name>/config.json` for
  /// each team. Read-modify-write: any field the UI doesn't know (agentId,
  /// sessionId, cwd, isActive, leadAgentId, ...) is preserved.
  ///
  /// Does NOT delete CLI directories for teams missing from [teams].
  /// CLI-side deletion is driven by the explicit [deleteTeam] entry point so
  /// that incremental edits don't accidentally clobber CLI-only entries
  /// (e.g. temp session teams the UI hasn't seen yet).
  Future<void> _syncToCliDir(List<TeamConfig> teams) async {
    for (final team in teams) {
      final teamDir = Directory(p.join(cliTeamsDir, team.name));
      await teamDir.create(recursive: true);
      final configFile = File(p.join(teamDir.path, 'config.json'));

      Map<String, Object?> existing = {};
      if (await configFile.exists()) {
        try {
          final raw = await configFile.readAsString();
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            existing = Map<String, Object?>.from(decoded);
          }
        } on FormatException {
          existing = {};
        } on FileSystemException {
          existing = {};
        }
      }

      existing['name'] = team.name;
      existing['createdAt'] = team.createdAt;
      if (team.loop != null) {
        existing['loop'] = team.loop;
      } else {
        existing.remove('loop');
      }
      existing['members'] =
          _mergeMembersForCli(team.members, existing['members']);

      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(existing),
      );
    }
  }

  /// Removes [name] from both the UI dir (`<rootDir>/<name>.json`) and the
  /// CLI dir (`<cliTeamsDir>/<name>/`, recursively). Best-effort: missing
  /// files/dirs are silently ignored. Only deletes a CLI directory if it
  /// actually has a `config.json` (i.e. looks like a team dir), to avoid
  /// nuking unrelated subdirs that happen to share the name.
  Future<void> deleteTeam(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final uiFile = File(p.join(rootDir, '$trimmed.json'));
    if (await uiFile.exists()) {
      try {
        await uiFile.delete();
      } on FileSystemException {
        // best effort
      }
    }

    final cliDir = Directory(p.join(cliTeamsDir, trimmed));
    if (await cliDir.exists()) {
      final configFile = File(p.join(cliDir.path, 'config.json'));
      if (await configFile.exists()) {
        try {
          await cliDir.delete(recursive: true);
        } on FileSystemException {
          // best effort
        }
      }
    }
  }

  List<Map<String, Object?>> _mergeMembersForCli(
    List<TeamMemberConfig> uiMembers,
    Object? existingRaw,
  ) {
    final existingByName = <String, Map<String, Object?>>{};
    if (existingRaw is List) {
      for (final m in existingRaw) {
        if (m is! Map) continue;
        final entry = Map<String, Object?>.from(m);
        final name = entry['name'] as String? ?? '';
        if (name.isNotEmpty) existingByName[name] = entry;
      }
    }
    return uiMembers.map((member) {
      final base = existingByName[member.name] ?? <String, Object?>{};
      base['name'] = member.name;
      base['joinedAt'] = member.joinedAt;
      if (member.dangerouslySkipPermissions) {
        base['dangerouslySkipPermissions'] = true;
      } else {
        base.remove('dangerouslySkipPermissions');
      }
      return base;
    }).toList(growable: false);
  }
}
