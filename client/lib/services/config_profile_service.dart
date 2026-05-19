import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/team_config.dart';

/// Launch-time environment for tool-isolated team profiles.
typedef TeamLaunchEnvironment = Map<String, String>;
typedef ConfigProfileDirectoryCreator = Future<void> Function(String path);

/// Ensures team runtime isolation directories and returns launch env vars.
///
/// Does not write provider native configs or team-level `llm_config.json`.
class ConfigProfileService {
  static const flashskyaiMetadataFileName = '.flashskyai.json';

  static const Map<String, Object?> defaultFlashskyaiMetadata = {
    'hasCompletedOnboarding': true,
  };
  ConfigProfileService({
    required this.basePath,
    ConfigProfileDirectoryCreator? createDirectory,
  }) : _createDirectory = createDirectory ?? _createLocalDirectory;

  final String basePath;
  final ConfigProfileDirectoryCreator _createDirectory;

  String get configProfilesDir => p.join(basePath, 'config-profiles');

  String get commonFlashskyaiDir =>
      p.join(configProfilesDir, 'common', 'flashskyai');

  String get commonFlashskyaiLlmConfigFile =>
      p.join(commonFlashskyaiDir, 'llm_config.json');

  String commonProfileDirForTool(String tool) =>
      p.join(configProfilesDir, 'common', tool.trim());

  String teamProfileDir(String teamId) =>
      p.join(configProfilesDir, 'teams', teamId.trim());

  String teamToolDir(String teamId, String tool) =>
      p.join(teamProfileDir(teamId), tool);

  String teamFlashskyaiMetadataFile(String teamId) =>
      p.join(teamToolDir(teamId, 'flashskyai'), flashskyaiMetadataFileName);

  Future<void> ensureCommonProfiles() async {
    await _createDirectory(commonFlashskyaiDir);
  }

  Future<void> ensureTeamProfile(
    String teamId, {
    TeamCli cli = TeamCli.flashskyai,
  }) async {
    final trimmed = teamId.trim();
    if (trimmed.isEmpty) return;

    await _createDirectory(teamToolDir(trimmed, cli.value));
    switch (cli) {
      case TeamCli.flashskyai:
        await ensureCommonProfiles();
        await ensureTeamFlashskyaiDefaults(trimmed);
      case TeamCli.codex:
      case TeamCli.claude:
        break;
    }
  }

  /// Seeds `.flashskyai.json` so the CLI skips first-run onboarding UI.
  Future<void> ensureTeamFlashskyaiDefaults(String teamId) async {
    final trimmed = teamId.trim();
    if (trimmed.isEmpty) return;

    final file = File(teamFlashskyaiMetadataFile(trimmed));
    if (await file.exists()) return;

    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(defaultFlashskyaiMetadata),
    );
  }

  /// Creates dirs for [cli] and returns launch env vars for that CLI only.
  Future<TeamLaunchEnvironment> prepareTeamLaunch({
    required String teamId,
    TeamCli cli = TeamCli.flashskyai,
    List<TeamMemberConfig> members = const [],
    String workingDirectory = '',
  }) async {
    final trimmedTeamId = teamId.trim();
    if (trimmedTeamId.isEmpty) {
      return const {};
    }

    await ensureTeamProfile(trimmedTeamId, cli: cli);
    if (cli == TeamCli.claude) {
      await _writeClaudeRoster(
        teamId: trimmedTeamId,
        members: members,
        workingDirectory: workingDirectory,
      );
    }

    return switch (cli) {
      TeamCli.flashskyai => {
        'FLASHSKYAI_CONFIG_DIR': teamToolDir(trimmedTeamId, 'flashskyai'),
        'LLM_CONFIG_PATH': commonFlashskyaiLlmConfigFile,
      },
      TeamCli.codex => {'CODEX_HOME': teamToolDir(trimmedTeamId, 'codex')},
      TeamCli.claude => {
        'CLAUDE_CONFIG_DIR': teamToolDir(trimmedTeamId, 'claude'),
        'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS': '1',
      },
    };
  }

  Future<void> _writeClaudeRoster({
    required String teamId,
    required List<TeamMemberConfig> members,
    required String workingDirectory,
  }) async {
    final claudeDir = teamToolDir(teamId, 'claude');
    final roster = File(
      p.join(claudeDir, 'teams', _safeClaudeTeamName(teamId), 'config.json'),
    );

    final existing = await _readJsonObject(roster);
    final existingMembersByName = <String, Map<String, Object?>>{};
    final rawExistingMembers = existing['members'];
    if (rawExistingMembers is List) {
      for (final rawMember in rawExistingMembers) {
        if (rawMember is! Map) continue;
        final memberJson = Map<String, Object?>.from(rawMember);
        final name = memberJson['name']?.toString();
        if (name != null && name.isNotEmpty) {
          existingMembersByName[name] = memberJson;
        }
      }
    }

    final createdAt = existing['createdAt'];
    final config = <String, Object?>{
      ...existing,
      'name': teamId,
      'createdAt': createdAt is int
          ? createdAt
          : DateTime.now().millisecondsSinceEpoch,
      'leadAgentId': 'team-lead@$teamId',
      'env': _claudeRosterEnv(existing['env']),
      'members': [
        for (final member in members.where((member) => member.isValid))
          _claudeRosterMember(
            teamId: teamId,
            member: member,
            existing: existingMembersByName[member.name],
            workingDirectory: workingDirectory,
          ),
      ],
    };

    await roster.parent.create(recursive: true);
    await roster.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
    );
  }

  Map<String, Object?> _claudeRosterMember({
    required String teamId,
    required TeamMemberConfig member,
    required Map<String, Object?>? existing,
    required String workingDirectory,
  }) {
    final existingMember = existing ?? const <String, Object?>{};
    final joinedAt = existingMember['joinedAt'];
    final memberJson = <String, Object?>{
      ...existingMember,
      'agentId': '${member.name}@$teamId',
      'name': member.name,
      'joinedAt': joinedAt is int ? joinedAt : member.joinedAt,
      'tmuxPaneId': '',
      'cwd': existingMember.containsKey('cwd')
          ? existingMember['cwd']
          : workingDirectory,
      'subscriptions': <Object?>[],
      if (member.model.trim().isNotEmpty) 'model': member.model.trim(),
    };

    if (existingMember.containsKey('sessionId')) {
      memberJson['sessionId'] = existingMember['sessionId'];
    }
    if (existingMember.containsKey('isActive')) {
      memberJson['isActive'] = existingMember['isActive'];
    }
    if (member.name == 'team-lead') {
      memberJson['agentType'] = 'team-lead';
    } else {
      memberJson.remove('agentType');
    }

    return memberJson;
  }

  static Map<String, Object?> _claudeRosterEnv(Object? existing) {
    final env = <String, Object?>{};
    if (existing is Map) {
      for (final entry in existing.entries) {
        final key = entry.key;
        if (key is String) {
          env[key] = entry.value;
        }
      }
    }
    env['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'] = '1';
    return env;
  }

  static Future<Map<String, Object?>> _readJsonObject(File file) async {
    if (!await file.exists()) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } on FormatException {
      return const <String, Object?>{};
    }
    return const <String, Object?>{};
  }

  static String _safeClaudeTeamName(String teamId) =>
      teamId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');

  static Future<void> _createLocalDirectory(String path) =>
      Directory(path).create(recursive: true);
}
