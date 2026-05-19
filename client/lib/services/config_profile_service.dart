import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/team_config.dart';

/// Launch-time environment for tool-isolated team profiles.
typedef TeamLaunchEnvironment = Map<String, String>;
typedef ConfigProfileDirectoryCreator = Future<void> Function(String path);

/// Profile directory key when launching without a chat [AppSession].
const configProfileAdhocSessionId = '_adhoc';

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

  /// Team metadata scope: `config-profiles/teams/<teamId>/`.
  String teamScopeDir(String teamId) =>
      p.join(configProfilesDir, 'teams', teamId.trim());

  /// Per-session scope: `config-profiles/teams/<teamId>/<sessionId>/`.
  String sessionProfileDir(String teamId, String sessionId) =>
      p.join(teamScopeDir(teamId), sessionId.trim());

  String sessionToolDir(String teamId, String sessionId, String tool) =>
      p.join(sessionProfileDir(teamId, sessionId), tool.trim());

  String sessionClaudeMemberSettingsFile(
    String teamId,
    String sessionId,
    TeamMemberConfig member,
  ) =>
      p.join(
        sessionToolDir(teamId, sessionId, 'claude'),
        'settings',
        '${_safeClaudePathName(member.name)}.json',
      );

  String sessionFlashskyaiMetadataFile(String teamId, String sessionId) =>
      p.join(
        sessionToolDir(teamId, sessionId, 'flashskyai'),
        flashskyaiMetadataFileName,
      );

  String sessionClaudeMetadataFile(String teamId, String sessionId) =>
      p.join(
        sessionToolDir(teamId, sessionId, 'claude'),
        claudeMetadataFileName,
      );

  Future<void> ensureCommonProfiles() async {
    await _createDirectory(commonFlashskyaiDir);
  }

  /// Ensures the team container exists under `config-profiles/teams/<teamId>/`.
  Future<void> ensureTeamProfile(
    String teamId, {
    TeamCli cli = TeamCli.flashskyai,
  }) async {
    final trimmed = teamId.trim();
    if (trimmed.isEmpty) return;
    await _createDirectory(teamScopeDir(trimmed));
  }

  Future<void> ensureSessionProfile(
    String teamId,
    String sessionId, {
    TeamCli cli = TeamCli.flashskyai,
  }) async {
    final trimmedTeamId = teamId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedTeamId.isEmpty || trimmedSessionId.isEmpty) return;

    await ensureTeamProfile(trimmedTeamId);
    await _createDirectory(
      sessionToolDir(trimmedTeamId, trimmedSessionId, cli.value),
    );
    switch (cli) {
      case TeamCli.flashskyai:
        await ensureCommonProfiles();
        await ensureSessionFlashskyaiDefaults(trimmedTeamId, trimmedSessionId);
      case TeamCli.codex:
        break;
      case TeamCli.claude:
        await ensureSessionClaudeDefaults(trimmedTeamId, trimmedSessionId);
        break;
    }
  }

  Future<void> ensureSessionFlashskyaiDefaults(
    String teamId,
    String sessionId,
  ) async {
    final file = File(sessionFlashskyaiMetadataFile(teamId, sessionId));
    if (await file.exists()) return;

    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(defaultFlashskyaiMetadata),
    );
  }

  Future<void> ensureSessionClaudeDefaults(String teamId, String sessionId) async {
    final file = File(sessionClaudeMetadataFile(teamId, sessionId));
    if (await file.exists()) return;

    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(defaultClaudeMetadata),
    );
  }

  /// Creates dirs for [cli] and returns launch env vars for that CLI only.
  ///
  /// [teamId] is [TeamConfig.id]. [runtimeTeamId] is the chat session id (CLI
  /// `--team-name`); when empty, uses [configProfileAdhocSessionId] for paths.
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

    final scope = _resolveLaunchScope(
      teamId: trimmedTeamId,
      runtimeTeamId: runtimeTeamId,
    );

    await ensureSessionProfile(
      scope.teamId,
      scope.sessionId,
      cli: cli,
    );
    if (cli == TeamCli.claude) {
      await _writeClaudeSettings(scope, claudeSettings);
      await _writeClaudeRoster(
        scope: scope,
        members: members,
        workingDirectory: workingDirectory,
      );
      await _writeClaudeMemberProfiles(
        scope: scope,
        members: members,
        launchedMember: member,
        providerSettings: claudeSettings,
        providerSettingsByMember: claudeSettingsByMember,
      );
    }

    return switch (cli) {
      TeamCli.flashskyai => {
        'FLASHSKYAI_CONFIG_DIR': sessionToolDir(
          scope.teamId,
          scope.sessionId,
          'flashskyai',
        ),
        'LLM_CONFIG_PATH': commonFlashskyaiLlmConfigFile,
      },
      TeamCli.codex => {
        'CODEX_HOME': sessionToolDir(scope.teamId, scope.sessionId, 'codex'),
      },
      TeamCli.claude => {
        'CLAUDE_CONFIG_DIR': sessionToolDir(
          scope.teamId,
          scope.sessionId,
          'claude',
        ),
        if (member != null && member.isValid)
          claudeSettingsFileEnvKey: sessionClaudeMemberSettingsFile(
            scope.teamId,
            scope.sessionId,
            member,
          ),
        'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS': '1',
      },
    };
  }

  static _LaunchProfileScope _resolveLaunchScope({
    required String teamId,
    required String runtimeTeamId,
  }) {
    final runtime = runtimeTeamId.trim();
    final sessionId = runtime.isNotEmpty ? runtime : configProfileAdhocSessionId;
    final cliTeamName = runtime.isNotEmpty ? runtime : teamId;
    return _LaunchProfileScope(
      teamId: teamId,
      sessionId: sessionId,
      cliTeamName: cliTeamName,
    );
  }

  Future<void> _writeClaudeSettings(
    _LaunchProfileScope scope,
    Map<String, Object?>? providerSettings,
  ) async {
    final file = File(
      p.join(
        sessionToolDir(scope.teamId, scope.sessionId, 'claude'),
        'settings.json',
      ),
    );
    final settings = _claudeTeamSettings(providerSettings);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings),
    );
  }

  Future<void> _writeClaudeRoster({
    required _LaunchProfileScope scope,
    required List<TeamMemberConfig> members,
    required String workingDirectory,
  }) async {
    final claudeDir = sessionToolDir(scope.teamId, scope.sessionId, 'claude');
    final roster = File(
      p.join(
        claudeDir,
        'teams',
        _safeClaudeTeamName(scope.cliTeamName),
        'config.json',
      ),
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

    final cliTeamName = scope.cliTeamName;
    final createdAt = existing['createdAt'];
    final config = <String, Object?>{
      ...existing,
      'name': cliTeamName,
      'createdAt': createdAt is int
          ? createdAt
          : DateTime.now().millisecondsSinceEpoch,
      'leadAgentId': 'team-lead@$cliTeamName',
      'env': _claudeRosterEnv(existing['env']),
      'members': [
        for (final member in members.where((member) => member.isValid))
          _claudeRosterMember(
            teamId: cliTeamName,
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
    required _LaunchProfileScope scope,
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
        scope: scope,
        member: member,
        providerSettings:
            providerSettingsByMember[member.id] ??
            providerSettingsByMember[member.name] ??
            providerSettings,
      );
    }
  }

  Future<void> _writeClaudeMemberProfile({
    required _LaunchProfileScope scope,
    required TeamMemberConfig member,
    required Map<String, Object?>? providerSettings,
  }) async {
    final file = File(
      sessionClaudeMemberSettingsFile(scope.teamId, scope.sessionId, member),
    );
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

class _LaunchProfileScope {
  const _LaunchProfileScope({
    required this.teamId,
    required this.sessionId,
    required this.cliTeamName,
  });

  final String teamId;
  final String sessionId;
  final String cliTeamName;
}
