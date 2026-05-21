import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/team_config.dart';
import '../utils/team_member_naming.dart';
import 'app_storage.dart';
import 'claude_team_roster_service.dart';
import 'cli_data_layout.dart';
import 'io/filesystem.dart';

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
  static const flashskyaiSettingsFileName = 'settings.json';
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
  }) : _fs = fs ?? AppStorage.fs,
       layout =
           layout ??
           CliDataLayout(
             teampilotRoot: basePath,
             fs: fs ?? AppStorage.fs,
           );

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
  ) {
    final safeName = member.name == TeamMemberNaming.teamLeadName
        ? TeamMemberNaming.teamLeadName
        : TeamMemberNaming.slugMemberName(member.name);
    return _pathContext.join(
      sessionToolDir(teamId, sessionId, 'claude'),
      'settings',
      '${ClaudeTeamRosterService.safeClaudePathSegment(safeName)}.json',
    );
  }

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
    TeamConfig? team,
    String? leadSessionId,
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
    switch (cli) {
      case TeamCli.flashskyai:
        await _writeFlashskyaiMetadata(scope, workingDirectory);
        await _writeFlashskyaiSettings(scope);
        break;
      case TeamCli.claude:
        await _writeClaudeMetadata(scope, workingDirectory);
        await _writeClaudeSettings(
          scope,
          claudeSettings,
          effortLevel: team?.claudeEffortLevel ?? 'xhigh',
          teammateMode: team?.claudeTeammateMode ?? 'in-process',
        );
        await _writeClaudeRoster(
          scope: scope,
          members: members,
          workingDirectory: workingDirectory,
          description: team?.description ?? '',
          leadSessionId: leadSessionId,
          teammateMode: team?.claudeTeammateMode ?? 'in-process',
        );
        await _writeClaudeMemberProfiles(
          scope: scope,
          members: members,
          launchedMember: member,
          providerSettings: claudeSettings,
          providerSettingsByMember: claudeSettingsByMember,
        );
        break;
      case TeamCli.codex:
        break;
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
    Map<String, Object?>? providerSettings, {
    required String effortLevel,
    required String teammateMode,
  }) async {
    final file = _pathContext.join(
      sessionToolDir(scope.teamId, scope.sessionId, 'claude'),
      'settings.json',
    );
    final settings = _claudeTeamSettings(
      providerSettings,
      effortLevel: effortLevel,
      teammateMode: teammateMode,
    );
    await _fs.atomicWrite(
      file,
      const JsonEncoder.withIndent('  ').convert(settings),
    );
  }

  Future<void> _writeClaudeMetadata(
    _LaunchProfileScope scope,
    String workingDirectory,
  ) async {
    final metadata = _metadataWithTrustedProject(
      defaultClaudeMetadata,
      workingDirectory,
    );
    final metadataPath = sessionClaudeMetadataFile(
      scope.teamId,
      scope.sessionId,
    );
    await _fs.atomicWrite(
      metadataPath,
      const JsonEncoder.withIndent('  ').convert(metadata),
    );
  }

  Future<void> _writeFlashskyaiMetadata(
    _LaunchProfileScope scope,
    String workingDirectory,
  ) async {
    final metadata = _metadataWithTrustedProject(
      defaultFlashskyaiMetadata,
      workingDirectory,
    );
    final metadataPath = sessionFlashskyaiMetadataFile(
      scope.teamId,
      scope.sessionId,
    );
    await _fs.atomicWrite(
      metadataPath,
      const JsonEncoder.withIndent('  ').convert(metadata),
    );
  }

  Future<void> _writeFlashskyaiSettings(_LaunchProfileScope scope) async {
    final file = _pathContext.join(
      sessionToolDir(scope.teamId, scope.sessionId, 'flashskyai'),
      flashskyaiSettingsFileName,
    );
    await _fs.atomicWrite(
      file,
      const JsonEncoder.withIndent('  ').convert(_flashskyaiTeamSettings()),
    );
  }

  String _projectMetadataKey(String workingDirectory) {
    final trimmed = workingDirectory.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('/')) {
      return trimmed.replaceAll('\\', '/');
    }
    return _pathContext.normalize(trimmed);
  }

  Map<String, Object?> _metadataWithTrustedProject(
    Map<String, Object?> baseMetadata,
    String workingDirectory,
  ) {
    final metadata = <String, Object?>{...baseMetadata};
    final normalizedWorkingDirectory = _projectMetadataKey(workingDirectory);
    if (normalizedWorkingDirectory.isNotEmpty) {
      metadata['projects'] = {
        normalizedWorkingDirectory: {'hasTrustDialogAccepted': true},
      };
    }
    return metadata;
  }

  Future<void> _writeClaudeRoster({
    required _LaunchProfileScope scope,
    required List<TeamMemberConfig> members,
    required String workingDirectory,
    required String description,
    required String teammateMode,
    String? leadSessionId,
  }) async {
    final claudeDir = sessionToolDir(scope.teamId, scope.sessionId, 'claude');
    final rosterDir = _pathContext.join(
      claudeDir,
      'teams',
      ClaudeTeamRosterService.safeClaudePathSegment(scope.cliTeamName),
    );
    final rosterPath = _pathContext.join(rosterDir, 'config.json');

    final cwd = ClaudeTeamRosterService.resolveWorkingDirectory(
      workingDirectory: workingDirectory,
      fallback: '',
    );

    Map<String, Object?>? existing;
    if ((await _fs.stat(rosterPath)).exists) {
      final raw = await _fs.readString(rosterPath);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          existing = Map<String, Object?>.from(
            decoded.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      }
    }

    final rosterService = ClaudeTeamRosterService(fs: _fs);
    final config = rosterService.mergeConfig(
      cliTeamName: scope.cliTeamName,
      members: members,
      cwd: cwd,
      teammateMode: teammateMode,
      description: description,
      leadSessionId: leadSessionId,
      existing: existing,
    );

    await _fs.atomicWrite(
      rosterPath,
      const JsonEncoder.withIndent('  ').convert(config),
    );
    await rosterService.ensureInboxes(
      rosterDir: rosterDir,
      members: members,
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

  static Map<String, Object?> _claudeTeamSettings(
    Map<String, Object?>? providerSettings, {
    required String effortLevel,
    required String teammateMode,
  }) {
    final settings = <String, Object?>{
      if (providerSettings != null) ...providerSettings,
    };
    final env = <String, Object?>{};
    final existingEnv = settings['env'];
    if (existingEnv is Map) {
      for (final entry in existingEnv.entries) {
        final key = entry.key;
        if (key is String) {
          env[key] = entry.value;
        }
      }
    }
    env['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'] = '1';
    env.putIfAbsent('CCGUI_CLI_LOGIN_AUTHORIZED', () => '1');
    env.putIfAbsent('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC', () => '1');
    settings['env'] = env;
    settings['effortLevel'] = effortLevel;
    settings['skipDangerousModePermissionPrompt'] = true;
    settings['teammateMode'] = teammateMode;
    return settings;
  }

  static Map<String, Object?> _claudeMemberSettings(
    Map<String, Object?>? providerSettings,
    TeamMemberConfig member,
  ) {
    final settings = _claudeTeamSettings(
      providerSettings,
      effortLevel: 'xhigh',
      teammateMode: 'in-process',
    );
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

  static Map<String, Object?> _flashskyaiTeamSettings() {
    return <String, Object?>{'skipDangerousModePermissionPrompt': true};
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
