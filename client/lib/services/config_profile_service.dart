import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../models/claude_credential_link_result.dart';
import '../models/team_config.dart';
import '../utils/project_path_utils.dart';
import '../utils/team_member_naming.dart';
import 'app_storage.dart';
import 'claude_official_provider.dart';
import 'claude_provider_credentials_service.dart';
import 'claude_team_roster_service.dart';
import 'cli_data_layout.dart';
import 'cli_plugin_registry_service.dart';
import 'io/filesystem.dart';
import 'rtk_detector.dart';
import 'rtk_hook_provisioner.dart';
import 'rtk_settings_merge.dart';

/// Launch-time environment for tool-isolated team profiles.
typedef TeamLaunchEnvironment = Map<String, String>;

class TeamLaunchOutcome {
  const TeamLaunchOutcome({
    required this.environment,
    this.warnings = const [],
  });

  final TeamLaunchEnvironment environment;
  final List<String> warnings;
}

/// Profile directory key when launching without a chat [AppSession].
const configProfileAdhocSessionId = '_adhoc';

/// [TeamLaunchOutcome.warnings] when RTK is enabled but dependencies are missing.
const rtkWarningEnabledNotFound = 'rtk_enabled_not_found';
const rtkWarningEnabledJqMissing = 'rtk_enabled_jq_missing';
const rtkWarningEnabledVersionTooOld = 'rtk_enabled_version_too_old';

/// Ensures team runtime isolation directories and returns launch env vars.
///
/// All paths are derived from [CliDataLayout]; this class is a thin wrapper
/// that adds CLI-specific bootstrap files (Claude roster, member settings,
/// metadata) on top of the canonical layout.
class ConfigProfileService {
  static const flashskyaiMetadataFileName = '.flashskyai.json';
  static const flashskyaiSettingsFileName = 'settings.json';
  static const flashskyaiConfigDirEnvKey = 'FLASHSKYAI_CONFIG_DIR';
  /// Transcript root (`projects/*.jsonl`); must match [flashskyaiConfigDirEnvKey].
  static const flashskyaiSessionHomeDirEnvKey = 'FLASHSKYAI_SESSION_HOME_DIR';
  static const claudeMetadataFileName = '.claude.json';
  static const claudeSettingsFileEnvKey = 'TEAMPILOT_CLAUDE_SETTINGS_FILE';

  static const Map<String, Object?> defaultFlashskyaiMetadata = {
    'hasCompletedOnboarding': true,
  };
  static const Map<String, Object?> defaultClaudeMetadata = {
    'hasCompletedOnboarding': true,
  };
  static const Map<String, Object?> defaultTrustedProjectConfig = {
    'hasTrustDialogAccepted': true,
    'projectOnboardingSeenCount': 1,
    'hasClaudeMdExternalIncludesApproved': true,
    'hasClaudeMdExternalIncludesWarningShown': true,
    'allowedTools': <Object?>[],
    'mcpServers': <String, Object?>{},
  };

  ConfigProfileService({
    required this.basePath,
    Filesystem? fs,
    CliDataLayout? layout,
    ClaudeProviderCredentialsService? claudeCredentialsService,
    Future<bool> Function()? loadRtkEnabled,
    RtkDetector? rtkDetector,
    RtkHookProvisioner? rtkHookProvisioner,
    Future<String> Function()? loadRtkHookScript,
  }) : _fs = fs ?? AppStorage.fs,
       layout =
           layout ??
           CliDataLayout(teampilotRoot: basePath, fs: fs ?? AppStorage.fs),
       _claudeCredentialsService = claudeCredentialsService,
       _loadRtkEnabled = loadRtkEnabled,
       _rtkDetector = rtkDetector ?? const RtkDetector(),
       _rtkHookProvisioner = rtkHookProvisioner,
       _loadRtkHookScript = loadRtkHookScript;

  final String basePath;
  final Filesystem _fs;
  final CliDataLayout layout;
  final ClaudeProviderCredentialsService? _claudeCredentialsService;
  final Future<bool> Function()? _loadRtkEnabled;
  final RtkDetector _rtkDetector;
  final RtkHookProvisioner? _rtkHookProvisioner;
  final Future<String> Function()? _loadRtkHookScript;

  ClaudeProviderCredentialsService get _claudeCredentials =>
      _claudeCredentialsService ??
      ClaudeProviderCredentialsService(fs: _fs, basePath: basePath);

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
    TeamConfig? team,
  }) async {
    final trimmedTeamId = teamId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedTeamId.isEmpty || trimmedSessionId.isEmpty) return;

    await ensureTeamProfile(trimmedTeamId, cli: cli);
    String? memberProvisionJson;
    await Future.wait([
      layout.ensureMemberInheritsTeam(
        trimmedTeamId,
        trimmedSessionId,
        cli.value,
      ),
      layout
          .provisionMemberPluginsFromTeam(
            trimmedTeamId,
            trimmedSessionId,
            cli.value,
          )
          .then((json) => memberProvisionJson = json),
    ]);
    if (cli == TeamCli.flashskyai || cli == TeamCli.claude) {
      await CliPluginRegistryService(
        fs: _fs,
        teampilotRoot: basePath,
        layout: layout,
      ).writeForSession(
        teamId: trimmedTeamId,
        sessionId: trimmedSessionId,
        tool: cli.value,
        team: team,
        memberProvisionJson: memberProvisionJson,
      );
    }
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
  Future<TeamLaunchOutcome> prepareTeamLaunch({
    required String teamId,
    String runtimeTeamId = '',
    TeamCli cli = TeamCli.flashskyai,
    List<TeamMemberConfig> members = const [],
    TeamMemberConfig? member,
    String workingDirectory = '',
    List<String> additionalDirectories = const [],
    Map<String, Object?>? claudeSettings,
    Map<String, Map<String, Object?>> claudeSettingsByMember = const {},
    TeamConfig? team,
    String? leadSessionId,
    String? claudeProviderId,
  }) async {
    final trimmedTeamId = teamId.trim();
    if (trimmedTeamId.isEmpty) {
      return const TeamLaunchOutcome(environment: {});
    }

    final warnings = <String>[];
    await _collectRtkWarnings(warnings);

    final scope = _resolveLaunchScope(
      teamId: trimmedTeamId,
      runtimeTeamId: runtimeTeamId,
    );

    await ensureSessionProfile(
      scope.teamId,
      scope.sessionId,
      cli: cli,
      team: team,
    );
    switch (cli) {
      case TeamCli.flashskyai:
        await _writeFlashskyaiMetadata(
          scope,
          workingDirectory,
          additionalDirectories: additionalDirectories,
        );
        await _writeFlashskyaiSettings(scope);
        break;
      case TeamCli.claude:
        await _writeClaudeMetadata(
          scope,
          workingDirectory,
          additionalDirectories: additionalDirectories,
        );
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
        final providerId = claudeProviderId?.trim() ?? '';
        if (providerId.isNotEmpty &&
            claudeSettings != null &&
            isOfficialClaudeSettings(claudeSettings)) {
          final sessionClaudeDir = sessionToolDir(
            scope.teamId,
            scope.sessionId,
            'claude',
          );
          final link = await _claudeCredentials.ensureLinked(
            sessionClaudeDir,
            providerId,
          );
          if (link == CredentialLinkResult.missing) {
            warnings.add('claude_credentials_missing');
          }
        }
        break;
      case TeamCli.codex:
        break;
    }

    return TeamLaunchOutcome(
      environment: switch (cli) {
      TeamCli.flashskyai => _flashskyaiTeamLaunchEnvironment(scope),
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
    },
      warnings: warnings,
    );
  }

  Map<String, String> _flashskyaiTeamLaunchEnvironment(_LaunchProfileScope scope) {
    final memberDir = sessionToolDir(
      scope.teamId,
      scope.sessionId,
      'flashskyai',
    );
    return {
      flashskyaiConfigDirEnvKey: memberDir,
      flashskyaiSessionHomeDirEnvKey: memberDir,
      'LLM_CONFIG_PATH': appFlashskyaiLlmConfigFile,
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
    await _writeSettingsFile(
      file,
      settings,
      memberToolDir: sessionToolDir(scope.teamId, scope.sessionId, 'claude'),
    );
  }

  Future<void> _writeClaudeMetadata(
    _LaunchProfileScope scope,
    String workingDirectory, {
    List<String> additionalDirectories = const [],
  }) async {
    final metadataPath = sessionClaudeMetadataFile(
      scope.teamId,
      scope.sessionId,
    );
    final metadata = await _metadataWithTrustedProjects(
      metadataPath: metadataPath,
      defaultMetadata: defaultClaudeMetadata,
      directories: [workingDirectory, ...additionalDirectories],
    );
    await _fs.atomicWrite(
      metadataPath,
      const JsonEncoder.withIndent('  ').convert(metadata),
    );
  }

  Future<void> _writeFlashskyaiMetadata(
    _LaunchProfileScope scope,
    String workingDirectory, {
    List<String> additionalDirectories = const [],
  }) async {
    final metadataPath = sessionFlashskyaiMetadataFile(
      scope.teamId,
      scope.sessionId,
    );
    final directories = [workingDirectory, ...additionalDirectories];
    if (await _trustedProjectsAlreadyCurrent(metadataPath, directories)) {
      return;
    }
    final metadata = await _metadataWithTrustedProjects(
      metadataPath: metadataPath,
      defaultMetadata: defaultFlashskyaiMetadata,
      directories: directories,
    );
    await _writeJsonIfChanged(metadataPath, metadata);
  }

  Future<bool> _trustedProjectsAlreadyCurrent(
    String metadataPath,
    Iterable<String> directories,
  ) async {
    final trustedKeys = {
      for (final dir in directories) ...projectMetadataKeys(dir),
    };
    if (trustedKeys.isEmpty) return false;

    final metadata = await _readMetadataFile(
      metadataPath,
      defaultFlashskyaiMetadata,
    );
    final projects = metadata['projects'];
    if (projects is! Map) return false;

    for (final key in trustedKeys) {
      final project = projects[key];
      if (project is! Map) return false;
      if (project['hasTrustDialogAccepted'] != true) return false;
    }
    return true;
  }

  Future<void> _writeFlashskyaiSettings(_LaunchProfileScope scope) async {
    final file = _pathContext.join(
      sessionToolDir(scope.teamId, scope.sessionId, 'flashskyai'),
      flashskyaiSettingsFileName,
    );
    final memberToolDir = sessionToolDir(scope.teamId, scope.sessionId, 'flashskyai');
    final teamDefaults = _flashskyaiTeamSettings();
    if (await _flashskyaiSettingsAlreadyCurrent(file, teamDefaults) &&
        !await _isRtkEnabled()) {
      return;
    }
    var merged = await _flashskyaiTeamSettingsMerged(file);
    merged = await _maybeApplyRtk(merged, memberToolDir);
    await _writeJsonIfChanged(file, merged);
  }

  Future<bool> _flashskyaiSettingsAlreadyCurrent(
    String path,
    Map<String, Object?> teamDefaults,
  ) async {
    if (!(await _fs.stat(path)).isFile) return false;
    final existing = await _readSettingsFile(path);
    for (final entry in teamDefaults.entries) {
      if (entry.key == 'enabledPlugins') continue;
      if (existing[entry.key] != entry.value) return false;
    }
    return true;
  }

  Future<Map<String, Object?>> _flashskyaiTeamSettingsMerged(String path) async {
    final existing = await _readSettingsFile(path);
    final merged = Map<String, Object?>.from(_flashskyaiTeamSettings());
    final enabledPlugins = existing['enabledPlugins'];
    if (enabledPlugins is Map && enabledPlugins.isNotEmpty) {
      merged['enabledPlugins'] = enabledPlugins;
    }
    return merged;
  }

  Future<void> _writeJsonIfChanged(
    String path,
    Map<String, Object?> value,
  ) async {
    final encoded = const JsonEncoder.withIndent('  ').convert(value);
    final existing = await _fs.readString(path);
    if (existing == encoded) {
      return;
    }
    await _fs.atomicWrite(path, encoded);
  }

  /// Writes team defaults without dropping [enabledPlugins] from plugin registry.
  Future<void> _writeSettingsFile(
    String path,
    Map<String, Object?> settings, {
    String? memberToolDir,
  }) async {
    final existing = await _readSettingsFile(path);
    final enabledPlugins = existing['enabledPlugins'];
    var merged = Map<String, Object?>.from(settings);
    if (enabledPlugins is Map && enabledPlugins.isNotEmpty) {
      merged['enabledPlugins'] = enabledPlugins;
    }
    merged = await _maybeApplyRtk(merged, memberToolDir);
    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(merged),
    );
  }

  Future<bool> _isRtkEnabled() async {
    final loader = _loadRtkEnabled;
    if (loader == null) return false;
    return loader();
  }

  RtkHookProvisioner _resolveRtkProvisioner() {
    return _rtkHookProvisioner ??
        RtkHookProvisioner(
          fs: _fs,
          loadHookScript:
              _loadRtkHookScript ??
              () => rootBundle.loadString('assets/rtk/rtk-rewrite.sh'),
        );
  }

  Future<void> _collectRtkWarnings(List<String> warnings) async {
    if (!await _isRtkEnabled()) return;
    final probe = await _rtkDetector.probe();
    if (!probe.found) {
      warnings.add(rtkWarningEnabledNotFound);
      return;
    }
    if (!probe.jqFound) {
      warnings.add(rtkWarningEnabledJqMissing);
      return;
    }
    final version = probe.version;
    if (version != null && !_rtkDetector.isVersionSupported(version)) {
      warnings.add(rtkWarningEnabledVersionTooOld);
    }
  }

  Future<Map<String, Object?>> _maybeApplyRtk(
    Map<String, Object?> settings,
    String? memberToolDir,
  ) async {
    final toolDir = memberToolDir?.trim() ?? '';
    if (toolDir.isEmpty) return settings;
    if (!await _isRtkEnabled()) return settings;

    final probe = await _rtkDetector.probe();
    if (!probe.isReady) return settings;

    final provisioner = _resolveRtkProvisioner();
    final scriptPath = await provisioner.provisionMemberToolDir(toolDir);
    final hookCommand = provisioner.hookCommandForPath(scriptPath);
    return const RtkSettingsMerge().mergeIntoSettings(
      base: settings,
      hookCommand: hookCommand,
    );
  }

  Future<Map<String, Object?>> _readSettingsFile(String path) async {
    if (!(await _fs.stat(path)).exists) return {};
    final raw = await _fs.readString(path);
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, Object?>.from(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } on Object {
      return {};
    }
    return {};
  }

  Future<Map<String, Object?>> _readMetadataFile(
    String path,
    Map<String, Object?> defaults,
  ) async {
    if (!(await _fs.stat(path)).exists) {
      return {...defaults};
    }
    final raw = await _fs.readString(path);
    if (raw == null || raw.trim().isEmpty) {
      return {...defaults};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, Object?>.from(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } on Object {
      return {...defaults};
    }
    return {...defaults};
  }

  Future<Map<String, Object?>> _metadataWithTrustedProjects({
    required String metadataPath,
    required Map<String, Object?> defaultMetadata,
    required Iterable<String> directories,
  }) async {
    final metadata = await _readMetadataFile(metadataPath, defaultMetadata);
    final trustedKeys = <String>{
      for (final dir in directories) ...projectMetadataKeys(dir),
    };
    if (trustedKeys.isEmpty) {
      return metadata;
    }

    final existingProjects = metadata['projects'];
    final projects = existingProjects is Map
        ? Map<String, Object?>.from(
            existingProjects.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
        : <String, Object?>{};

    for (final key in trustedKeys) {
      final existing = projects[key];
      final projectConfig = existing is Map
          ? Map<String, Object?>.from(
              existing.map(
                (entryKey, value) => MapEntry(entryKey.toString(), value),
              ),
            )
          : <String, Object?>{...defaultTrustedProjectConfig};
      for (final entry in defaultTrustedProjectConfig.entries) {
        projectConfig.putIfAbsent(entry.key, () => entry.value);
      }
      projectConfig['hasTrustDialogAccepted'] = true;
      projectConfig['hasClaudeMdExternalIncludesApproved'] = true;
      projectConfig['hasClaudeMdExternalIncludesWarningShown'] = true;
      projects[key] = projectConfig;
    }
    metadata['projects'] = projects;
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
    await rosterService.ensureInboxes(rosterDir: rosterDir, members: members);
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
    await _writeSettingsFile(
      file,
      settings,
      memberToolDir: sessionToolDir(scope.teamId, scope.sessionId, 'claude'),
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
