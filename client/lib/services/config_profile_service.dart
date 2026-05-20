import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/team_config.dart';
import 'cli_data_layout.dart';
import 'io/filesystem.dart';
import 'io/local_filesystem.dart';

/// Launch-time environment for tool-isolated team profiles.
typedef TeamLaunchEnvironment = Map<String, String>;

/// Profile directory key when launching without a chat [AppSession].
const configProfileAdhocSessionId = '_adhoc';

/// Ensures team runtime isolation directories and returns launch env vars.
///
/// All paths are derived from [CliDataLayout]; this class is a thin wrapper
/// that adds CLI-specific bootstrap files (Claude roster, member settings,
/// metadata) on top of the canonical layout.
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
    Filesystem? fs,
    CliDataLayout? layout,
  }) : _fs = fs ?? LocalFilesystem(),
       layout =
           layout ??
           CliDataLayout(teampilotRoot: basePath, fs: fs ?? LocalFilesystem());

  final String basePath;
  final Filesystem _fs;
  final CliDataLayout layout;

  p.Context get _pathContext => _fs.pathContext;

  String get configProfilesDir => layout.configProfilesDir;

  /// App-level FlashskyAI provider catalog file (`config-profiles/flashskyai/llm_config.json`).
  String get appFlashskyaiLlmConfigFile => layout.appFlashskyaiLlmConfigFile;

  String appToolDir(String tool) => layout.appToolRoot(tool);

  /// Team metadata scope: `config-profiles/teams/<teamId>/`.
  String teamScopeDir(String teamId) =>
      _pathContext.join(configProfilesDir, 'teams', teamId.trim());

  /// Per-session member scope: `config-profiles/teams/<teamId>/members/<sessionId>/`.
  String sessionProfileDir(String teamId, String sessionId) =>
      _pathContext.join(teamScopeDir(teamId), 'members', sessionId.trim());

  String sessionToolDir(String teamId, String sessionId, String tool) =>
      layout.memberToolDir(teamId, sessionId, tool);

  String sessionClaudeMemberSettingsFile(
    String teamId,
    String sessionId,
    TeamMemberConfig member,
  ) => _pathContext.join(
    sessionToolDir(teamId, sessionId, 'claude'),
    'settings',
    '${_safeClaudePathName(member.name)}.json',
  );

  String sessionFlashskyaiMetadataFile(String teamId, String sessionId) =>
      _pathContext.join(
        sessionToolDir(teamId, sessionId, 'flashskyai'),
        flashskyaiMetadataFileName,
      );

  String sessionClaudeMetadataFile(String teamId, String sessionId) =>
      _pathContext.join(
        sessionToolDir(teamId, sessionId, 'claude'),
        claudeMetadataFileName,
      );

  /// Ensures the bare team scope directory exists.
  ///
  /// The team-level `{tool}/` subdirectory and inherited symlinks are
  /// provisioned lazily by [ensureSessionProfile] (i.e. only when a member
  /// actually launches the tool). Calling this on every load keeps the
  /// `teams/<id>/` UI metadata location in lockstep with addTeam without
  /// allocating empty tool roots.
  Future<void> ensureTeamProfile(
    String teamId, {
    TeamCli cli = TeamCli.flashskyai,
  }) async {
    final trimmed = teamId.trim();
    if (trimmed.isEmpty) return;
    await _fs.ensureDir(teamScopeDir(trimmed));
  }

  Future<void> ensureSessionProfile(
    String teamId,
    String sessionId, {
    TeamCli cli = TeamCli.flashskyai,
  }) async {
    final trimmedTeamId = teamId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedTeamId.isEmpty || trimmedSessionId.isEmpty) return;

    await ensureTeamProfile(trimmedTeamId, cli: cli);
    await layout.ensureMemberInheritsTeam(
      trimmedTeamId,
      trimmedSessionId,
      cli.value,
    );
    switch (cli) {
      case TeamCli.flashskyai:
        await layout.ensureAppToolLayout('flashskyai');
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
    final file = sessionFlashskyaiMetadataFile(teamId, sessionId);
    if ((await _fs.stat(file)).exists) return;

    await _fs.atomicWrite(
      file,
      const JsonEncoder.withIndent('  ').convert(defaultFlashskyaiMetadata),
    );
  }

  Future<void> ensureSessionClaudeDefaults(
    String teamId,
    String sessionId,
  ) async {
    final file = sessionClaudeMetadataFile(teamId, sessionId);
    if ((await _fs.stat(file)).exists) return;

    await _fs.atomicWrite(
      file,
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

    await ensureSessionProfile(scope.teamId, scope.sessionId, cli: cli);
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
        'LLM_CONFIG_PATH': appFlashskyaiLlmConfigFile,
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
    final sessionId = runtime.isNotEmpty
        ? runtime
        : configProfileAdhocSessionId;
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
    final file = _pathContext.join(
      sessionToolDir(scope.teamId, scope.sessionId, 'claude'),
      'settings.json',
    );
    final settings = _claudeTeamSettings(providerSettings);
    await _fs.atomicWrite(
      file,
      const JsonEncoder.withIndent('  ').convert(settings),
    );
  }

  Future<void> _writeClaudeRoster({
    required _LaunchProfileScope scope,
    required List<TeamMemberConfig> members,
    required String workingDirectory,
  }) async {
    final claudeDir = sessionToolDir(scope.teamId, scope.sessionId, 'claude');
    final roster = _pathContext.join(
      claudeDir,
      'teams',
      _safeClaudeTeamName(scope.cliTeamName),
      'config.json',
    );

    final cliTeamName = scope.cliTeamName;
    final config = <String, Object?>{
      'name': cliTeamName,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'leadAgentId': 'team-lead@$cliTeamName',
      'env': _claudeRosterEnv(null),
      'members': [
        for (final member in members.where((member) => member.isValid))
          _claudeRosterMember(
            teamId: cliTeamName,
            member: member,
            workingDirectory: workingDirectory,
          ),
      ],
    };

    await _fs.atomicWrite(
      roster,
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
    final file = sessionClaudeMemberSettingsFile(
      scope.teamId,
      scope.sessionId,
      member,
    );
    final settings = _claudeMemberSettings(providerSettings, member);
    await _fs.atomicWrite(
      file,
      const JsonEncoder.withIndent('  ').convert(settings),
    );
  }

  Map<String, Object?> _claudeRosterMember({
    required String teamId,
    required TeamMemberConfig member,
    required String workingDirectory,
  }) {
    final memberJson = <String, Object?>{
      'agentId': '${member.name}@$teamId',
      'name': member.name,
      'joinedAt': member.joinedAt,
      'tmuxPaneId': '',
      'cwd': workingDirectory,
      'subscriptions': <Object?>[],
      if (member.model.trim().isNotEmpty) 'model': member.model.trim(),
    };

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

  static String _safeClaudeTeamName(String teamId) =>
      _safeClaudePathName(teamId);

  static String _safeClaudePathName(String value) {
    final safe = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');
    return safe.isEmpty ? 'default' : safe;
  }
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
