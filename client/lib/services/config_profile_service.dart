import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/team_config.dart';

/// Launch-time environment for tool-isolated team profiles.
typedef TeamLaunchEnvironment = Map<String, String>;
typedef ConfigProfileDirectoryCreator = Future<void> Function(String path);

/// Ensures team runtime isolation directories and returns launch env vars.
///
/// Does not write team-level `llm_config.json`.
class ConfigProfileService {
  static const flashskyaiMetadataFileName = '.flashskyai.json';
  static const claudeMetadataFileName = '.claude.json';
  static const claudeSettingsFileEnvKey = 'TEAMPILOT_CLAUDE_SETTINGS_FILE';

  static const Map<String, Object?> defaultFlashskyaiMetadata = {
    'hasCompletedOnboarding': true,
  };
  static const Map<String, Object?> defaultClaudeMetadata = {
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

  String teamClaudeMemberSettingsFile(String teamId, TeamMemberConfig member) =>
      p.join(
        teamToolDir(teamId, 'claude'),
        'settings',
        '${_safeClaudePathName(member.name)}.json',
      );

  String teamFlashskyaiMetadataFile(String teamId) =>
      p.join(teamToolDir(teamId, 'flashskyai'), flashskyaiMetadataFileName);

  String teamClaudeMetadataFile(String teamId) =>
      p.join(teamToolDir(teamId, 'claude'), claudeMetadataFileName);

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
        break;
      case TeamCli.claude:
        await ensureTeamClaudeDefaults(trimmed);
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

  /// Seeds `.claude.json` so Claude Code skips the first-run onboarding UI.
  Future<void> ensureTeamClaudeDefaults(String teamId) async {
    final trimmed = teamId.trim();
    if (trimmed.isEmpty) return;

    final file = File(teamClaudeMetadataFile(trimmed));
    if (await file.exists()) return;

    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(defaultClaudeMetadata),
    );
  }

  /// Creates dirs for [cli] and returns launch env vars for that CLI only.
  ///
  /// [teamId] identifies the source team metadata. [runtimeTeamId], when set,
  /// identifies the launch-time profile directory used by one session.
  Future<TeamLaunchEnvironment> prepareTeamLaunch({
    required String teamId,
    String runtimeTeamId = '',
    TeamCli cli = TeamCli.flashskyai,
    List<TeamMemberConfig> members = const [],
    TeamMemberConfig? member,
    String workingDirectory = '',
    Map<String, Object?>? claudeSettings,
    Map<String, Map<String, Object?>> claudeSettingsByMember = const {},
  }) async {
    final trimmedTeamId = teamId.trim();
    if (trimmedTeamId.isEmpty) {
      return const {};
    }
    final profileTeamId = runtimeTeamId.trim().isNotEmpty
        ? runtimeTeamId.trim()
        : trimmedTeamId;

    await ensureTeamProfile(profileTeamId, cli: cli);
    if (cli == TeamCli.claude) {
      await _writeClaudeSettings(profileTeamId, claudeSettings);
      await _writeClaudeRoster(
        teamId: profileTeamId,
        members: members,
        workingDirectory: workingDirectory,
      );
      await _writeClaudeMemberProfiles(
        teamId: profileTeamId,
        members: members,
        launchedMember: member,
        providerSettings: claudeSettings,
        providerSettingsByMember: claudeSettingsByMember,
      );
    }

    return switch (cli) {
      TeamCli.flashskyai => {
        'FLASHSKYAI_CONFIG_DIR': teamToolDir(profileTeamId, 'flashskyai'),
        'LLM_CONFIG_PATH': commonFlashskyaiLlmConfigFile,
      },
      TeamCli.codex => {'CODEX_HOME': teamToolDir(profileTeamId, 'codex')},
      TeamCli.claude => {
        'CLAUDE_CONFIG_DIR': teamToolDir(profileTeamId, 'claude'),
        if (member != null && member.isValid)
          claudeSettingsFileEnvKey: teamClaudeMemberSettingsFile(
            profileTeamId,
            member,
          ),
        'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS': '1',
      },
    };
  }

  Future<void> _writeClaudeSettings(
    String teamId,
    Map<String, Object?>? providerSettings,
  ) async {
    final file = File(p.join(teamToolDir(teamId, 'claude'), 'settings.json'));
    final settings = _claudeTeamSettings(providerSettings);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings),
    );
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

  Future<void> _writeClaudeMemberProfiles({
    required String teamId,
    required List<TeamMemberConfig> members,
    required TeamMemberConfig? launchedMember,
    required Map<String, Object?>? providerSettings,
    required Map<String, Map<String, Object?>> providerSettingsByMember,
  }) async {
    final uniqueMembers = <String, TeamMemberConfig>{};
    for (final member in members.where((member) => member.isValid)) {
      uniqueMembers[member.name] = member;
    }
    final selected = launchedMember;
    if (selected != null && selected.isValid) {
      uniqueMembers[selected.name] = selected;
    }

    for (final member in uniqueMembers.values) {
      await _writeClaudeMemberProfile(
        teamId: teamId,
        member: member,
        providerSettings:
            providerSettingsByMember[member.id] ??
            providerSettingsByMember[member.name] ??
            providerSettings,
      );
    }
  }

  Future<void> _writeClaudeMemberProfile({
    required String teamId,
    required TeamMemberConfig member,
    required Map<String, Object?>? providerSettings,
  }) async {
    final file = File(teamClaudeMemberSettingsFile(teamId, member));
    final settings = _claudeMemberSettings(providerSettings, member);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings),
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

  static Map<String, Object?> _claudeTeamSettings(
    Map<String, Object?>? providerSettings,
  ) {
    final settings = <String, Object?>{
      if (providerSettings != null) ...providerSettings,
    };
    final env = _claudeRosterEnv(settings['env']);
    env.putIfAbsent('CCGUI_CLI_LOGIN_AUTHORIZED', () => '1');
    env.putIfAbsent('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC', () => '1');
    settings['env'] = env;
    settings.putIfAbsent('effortLevel', () => 'xhigh');
    settings.putIfAbsent('skipDangerousModePermissionPrompt', () => true);
    settings.putIfAbsent('teammateMode', () => 'in-process');
    return settings;
  }

  static Map<String, Object?> _claudeMemberSettings(
    Map<String, Object?>? providerSettings,
    TeamMemberConfig member,
  ) {
    final settings = _claudeTeamSettings(providerSettings);
    final model = member.model.trim();
    if (model.isNotEmpty) {
      final env = Map<String, Object?>.from(settings['env'] as Map);
      env['ANTHROPIC_MODEL'] = model;
      env['ANTHROPIC_DEFAULT_HAIKU_MODEL'] = model;
      env['ANTHROPIC_DEFAULT_SONNET_MODEL'] = model;
      env['ANTHROPIC_DEFAULT_OPUS_MODEL'] = model;
      settings['env'] = env;
    }
    return settings;
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
      _safeClaudePathName(teamId);

  static String _safeClaudePathName(String value) {
    final safe = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');
    return safe.isEmpty ? 'default' : safe;
  }

  static Future<void> _createLocalDirectory(String path) =>
      Directory(path).create(recursive: true);
}
