import 'dart:convert';
import 'package:path/path.dart' as p;

import '../../models/team_config.dart';
import '../../utils/project_path_utils.dart';
import '../../utils/team_member_naming.dart';
import '../storage/app_storage.dart';
import 'claude_provider_credentials_service.dart';
import '../team/claude_team_roster_service.dart';
import '../cli/cli_data_layout.dart';
import '../cli/registry/built_in_cli_tools.dart';
import '../cli/registry/capabilities/config_profile_capability.dart';
import '../cli/registry/config_profile/config_profile_context.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../cli/registry/config_profile/claude_config_profile_capability.dart';
import '../cli/registry/config_profile/flashskyai_config_profile_capability.dart';
import '../host/bundled_asset_loader.dart';
import '../host/host_execution_environment.dart';
import '../host/host_script_dialect.dart';
import '../host/script_file_hook_provisioner.dart';
import '../host/team_pilot_hook_scripts.dart';
import '../mcp/mcp_registry_service.dart';
import '../plugin/cli_plugin_registry_service.dart';
import '../io/filesystem.dart';
import '../session/member_role_provision.dart';
import '../storage/runtime_storage_context.dart';
import '../../models/extension_manifest.dart';
import '../extension/builtin_manifests.dart';
import '../extension/extension_detector.dart';
import '../extension/extension_provisioner.dart';
import '../team/team_lead_delegate_settings_merge.dart';
import '../team/team_lead_settings_merge.dart';

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
const rtkWarningEnabledDependencyMissing = 'rtk_enabled_dependency_missing';
const rtkWarningEnabledVersionTooOld = 'rtk_enabled_version_too_old';

/// Ensures team runtime isolation directories and returns launch env vars.
///
/// All paths are derived from [CliDataLayout]; this class is a thin wrapper
/// that adds CLI-specific bootstrap files (Claude roster, member settings,
/// metadata) on top of the canonical layout.
class ConfigProfileService implements ConfigProfileDelegate {
  static final _defaultCliRegistry = () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    return registry;
  }();

  static const _pluginRegistryCliIds = {'flashskyai', 'claude'};
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
    ExtensionDetector? extensionDetector,
    List<ExtensionManifest>? extensionManifests,
    ScriptFileHookProvisioner? rtkHookProvisioner,
    Future<String> Function(HostScriptDialect dialect)? loadRtkHookScript,
    ScriptFileHookProvisioner? teamLeadHookProvisioner,
    Future<String> Function(HostScriptDialect dialect)? loadTeamLeadHookScript,
    ScriptFileHookProvisioner? teamLeadDelegateHookProvisioner,
    Future<String> Function(HostScriptDialect dialect)? loadTeamLeadDelegateHookScript,
    HostExecutionEnvironment? hostEnvironment,
    CliToolRegistry? cliRegistry,
  }) : _fs = fs ?? AppStorage.fs,
       _cliRegistry = cliRegistry ?? _defaultCliRegistry,
       layout =
           layout ??
           CliDataLayout(teampilotRoot: basePath, fs: fs ?? AppStorage.fs),
       _claudeCredentialsService = claudeCredentialsService,
       _loadRtkEnabled = loadRtkEnabled,
       _extensionDetector = extensionDetector,
       _extensionManifests = extensionManifests,
       _rtkHookProvisioner = rtkHookProvisioner,
       _loadRtkHookScript = loadRtkHookScript,
       _teamLeadHookProvisioner = teamLeadHookProvisioner,
       _loadTeamLeadHookScript = loadTeamLeadHookScript,
       _teamLeadDelegateHookProvisioner = teamLeadDelegateHookProvisioner,
       _loadTeamLeadDelegateHookScript = loadTeamLeadDelegateHookScript,
       _hostEnvironment = hostEnvironment;

  @override
  final String basePath;
  final Filesystem _fs;
  @override
  final CliDataLayout layout;
  final ClaudeProviderCredentialsService? _claudeCredentialsService;
  final Future<bool> Function()? _loadRtkEnabled;
  final ExtensionDetector? _extensionDetector;
  final List<ExtensionManifest>? _extensionManifests;
  ExtensionProvisioner? _cachedExtensionProvisioner;
  final ScriptFileHookProvisioner? _rtkHookProvisioner;
  final Future<String> Function(HostScriptDialect dialect)? _loadRtkHookScript;
  final ScriptFileHookProvisioner? _teamLeadHookProvisioner;
  final Future<String> Function(HostScriptDialect dialect)? _loadTeamLeadHookScript;
  final ScriptFileHookProvisioner? _teamLeadDelegateHookProvisioner;
  final Future<String> Function(HostScriptDialect dialect)? _loadTeamLeadDelegateHookScript;
  final HostExecutionEnvironment? _hostEnvironment;
  final CliToolRegistry _cliRegistry;

  @override
  ClaudeProviderCredentialsService get claudeCredentials =>
      _claudeCredentialsService ??
      ClaudeProviderCredentialsService(fs: _fs, basePath: basePath);

  @override
  Filesystem get fs => _fs;

  @override
  p.Context get pathContext => _fs.pathContext;

  String get configProfilesDir => layout.configProfilesDir;

  /// App-level FlashskyAI provider catalog file (`config-profiles/flashskyai/llm_config.json`).
  @override
  String get appFlashskyaiLlmConfigFile => layout.appFlashskyaiLlmConfigFile;

  String appToolDir(String tool) => layout.appToolRoot(tool);

  /// Team metadata scope: `config-profiles/teams/<teamId>/`.
  String teamScopeDir(String teamId) =>
      pathContext.join(configProfilesDir, 'teams', teamId.trim());

  /// Per-session member scope: `config-profiles/teams/<teamId>/members/<sessionId>/`.
  String sessionProfileDir(String teamId, String sessionId) =>
      pathContext.join(teamScopeDir(teamId), 'members', sessionId.trim());

  @override
  String sessionToolDir(String teamId, String sessionId, String tool) =>
      layout.memberToolDir(teamId, sessionId, tool);

  @override
  String sessionClaudeMemberSettingsFile(
    String teamId,
    String sessionId,
    TeamMemberConfig member,
  ) {
    return pathContext.join(
      sessionToolDir(teamId, sessionId, 'claude'),
      'settings',
      '${ClaudeTeamRosterService.safeClaudePathSegment(member.id)}.json',
    );
  }

  @override
  String sessionFlashskyaiMetadataFile(String teamId, String sessionId) =>
      pathContext.join(
        sessionToolDir(teamId, sessionId, 'flashskyai'),
        flashskyaiMetadataFileName,
      );

  @override
  String sessionClaudeMetadataFile(String teamId, String sessionId) =>
      pathContext.join(
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
    Map<String, Map<String, Object?>>? extraMcpServers,
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
    if (_pluginRegistryCliIds.contains(cli.value)) {
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
    final cap = _cliRegistry.capability<ConfigProfileCapability>(cli.value);
    if (cap != null) {
      await cap.ensureSessionProfile(
        ConfigProfileSessionContext(
          teamId: trimmedTeamId,
          sessionId: trimmedSessionId,
          members: team?.members ?? const [],
          paths: this,
          team: team,
        ),
      );
    }
    await McpRegistryService(fs: _fs, layout: layout).writeForSession(
      teamId: trimmedTeamId,
      sessionId: trimmedSessionId,
      extraServers: extraMcpServers,
    );
  }

  Future<void> ensureSessionFlashskyaiDefaults(
    String teamId,
    String sessionId,
  ) async {
    const capability = FlashskyaiConfigProfileCapability();
    await capability.ensureSessionProfile(
      ConfigProfileSessionContext(
        teamId: teamId,
        sessionId: sessionId,
        members: const [],
        paths: this,
      ),
    );
  }

  Future<void> ensureSessionClaudeDefaults(
    String teamId,
    String sessionId,
  ) async {
    const capability = ClaudeConfigProfileCapability();
    await capability.ensureSessionProfile(
      ConfigProfileSessionContext(
        teamId: teamId,
        sessionId: sessionId,
        members: const [],
        paths: this,
      ),
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
    Map<String, Map<String, Object?>>? extraMcpServers,
  }) async {
    final trimmedTeamId = teamId.trim();
    if (trimmedTeamId.isEmpty) {
      return const TeamLaunchOutcome(environment: {});
    }

    final warnings = <String>[];
    await _collectRtkWarnings(warnings);

    final scope = resolveLaunchScope(
      teamId: trimmedTeamId,
      runtimeTeamId: runtimeTeamId,
    );

    await ensureSessionProfile(
      scope.teamId,
      scope.sessionId,
      cli: cli,
      team: team,
      extraMcpServers: extraMcpServers,
    );

    final cap = _cliRegistry.capability<ConfigProfileCapability>(cli.value);
    if (cap == null) {
      return TeamLaunchOutcome(
        environment: const {},
        warnings: [...warnings, 'unknown_cli_${cli.value}'],
      );
    }

    final claudeExtras = claudeSettings != null ||
            claudeProviderId != null ||
            claudeSettingsByMember.isNotEmpty
        ? ClaudeLaunchExtras(
            settings: claudeSettings,
            providerId: claudeProviderId,
            settingsByMember: claudeSettingsByMember,
          )
        : null;

    ConfigProfileLaunchContribution contribution;
    try {
      contribution = await cap.contributeLaunch(
        ConfigProfileLaunchContext(
          teamId: scope.teamId,
          sessionId: scope.sessionId,
          scope: scope,
          team: team,
          member: member,
          members: members,
          workingDirectory: workingDirectory,
          additionalDirectories: additionalDirectories,
          paths: this,
          claude: claudeExtras,
          leadSessionId: leadSessionId,
        ),
      );
    } on Object catch (e) {
      return TeamLaunchOutcome(
        environment: const {},
        warnings: [
          ...warnings,
          'config_profile_${cli.value}: $e',
        ],
      );
    }

    return TeamLaunchOutcome(
      environment: contribution.environment,
      warnings: [...warnings, ...contribution.warnings],
    );
  }

  static LaunchProfileScope resolveLaunchScope({
    required String teamId,
    required String runtimeTeamId,
  }) {
    final runtime = runtimeTeamId.trim();
    final sessionId = runtime.isNotEmpty
        ? runtime
        : configProfileAdhocSessionId;
    final cliTeamName = runtime.isNotEmpty ? runtime : teamId;
    return LaunchProfileScope(
      teamId: teamId,
      sessionId: sessionId,
      cliTeamName: cliTeamName,
    );
  }

  @override
  Future<Map<String, Object?>> readMetadataFile(
    String path,
    Map<String, Object?> defaults,
  ) =>
      _readMetadataFile(path, defaults);

  @override
  Future<void> writeJsonIfChanged(String path, Map<String, Object?> value) =>
      _writeJsonIfChanged(path, value);

  @override
  Future<Map<String, Object?>> metadataWithTrustedProjects({
    required String metadataPath,
    required Map<String, Object?> defaultMetadata,
    required Iterable<String> directories,
  }) =>
      _metadataWithTrustedProjects(
        metadataPath: metadataPath,
        defaultMetadata: defaultMetadata,
        directories: directories,
      );

  @override
  Future<bool> trustedProjectsAlreadyCurrent(
    String metadataPath,
    Iterable<String> directories,
  ) =>
      _trustedProjectsAlreadyCurrent(metadataPath, directories);

  @override
  Future<Map<String, Object?>> readSettingsFile(String path) =>
      _readSettingsFile(path);

  @override
  Future<void> writeSettingsFile(
    String path,
    Map<String, Object?> settings, {
    String? memberToolDir,
  }) =>
      _writeSettingsFile(path, settings, memberToolDir: memberToolDir);

  @override
  Future<bool> isRtkEnabled() => _isRtkEnabled();

  @override
  Future<Map<String, Object?>> maybeApplyRtk(
    Map<String, Object?> settings,
    String? memberToolDir,
  ) =>
      _maybeApplyRtk(settings, memberToolDir);

  @override
  Future<Map<String, Object?>> maybeApplyTeamLeadHooks(
    Map<String, Object?> settings,
    TeamMemberConfig member,
    String memberToolDir, {
    required bool forceTeamLeadDelegateMode,
  }) =>
      _maybeApplyTeamLeadHooks(
        settings,
        member,
        memberToolDir,
        forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
      );

  @override
  Future<String?> resolveAppendSystemPromptPath({
    required LaunchProfileScope scope,
    required String tool,
    required TeamMemberConfig member,
  }) =>
      _resolveAppendSystemPromptPath(scope: scope, tool: tool, member: member);

  @override
  HostExecutionEnvironment hostEnvironmentForProvision() =>
      _hostEnvironmentForProvision();

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

  HostExecutionEnvironment _hostEnvironmentForProvision() {
    if (_hostEnvironment != null) return _hostEnvironment;
    if (RuntimeStorageContext.isInstalled) {
      return HostExecutionEnvironment.fromStorage(RuntimeStorageContext.current);
    }
    return HostExecutionEnvironment.resolve();
  }

  ScriptFileHookProvisioner _resolveRtkProvisioner(
    HostExecutionEnvironment host,
  ) {
    return _rtkHookProvisioner ??
        ScriptFileHookProvisioner(
          fs: _fs,
          runner: host.scriptRunner,
          baseFileName: TeamPilotHookScripts.rtkRewrite,
          loadScript:
              _loadRtkHookScript ??
              (dialect) => loadBundledAssetString(
                switch (dialect) {
                  HostScriptDialect.bash => 'assets/rtk/rtk-rewrite.sh',
                  HostScriptDialect.powershell => 'assets/rtk/rtk-rewrite.ps1',
                },
              ),
        );
  }

  ScriptFileHookProvisioner _resolveTeamLeadHookProvisioner(
    HostExecutionEnvironment host,
  ) {
    return _teamLeadHookProvisioner ??
        ScriptFileHookProvisioner(
          fs: _fs,
          runner: host.scriptRunner,
          baseFileName: TeamPilotHookScripts.teamLeadSelf,
          loadScript:
              _loadTeamLeadHookScript ??
              (dialect) => loadBundledAssetString(
                switch (dialect) {
                  HostScriptDialect.bash =>
                    'assets/hooks/teampilot-deny-team-lead-self-message.sh',
                  HostScriptDialect.powershell =>
                    'assets/hooks/teampilot-deny-team-lead-self-message.ps1',
                },
              ),
        );
  }

  ScriptFileHookProvisioner _resolveTeamLeadDelegateHookProvisioner(
    HostExecutionEnvironment host,
  ) {
    return _teamLeadDelegateHookProvisioner ??
        ScriptFileHookProvisioner(
          fs: _fs,
          runner: host.scriptRunner,
          baseFileName: TeamPilotHookScripts.teamLeadDelegate,
          loadScript:
              _loadTeamLeadDelegateHookScript ??
              (dialect) => loadBundledAssetString(
                switch (dialect) {
                  HostScriptDialect.bash =>
                    'assets/hooks/teampilot-team-lead-delegate-only.sh',
                  HostScriptDialect.powershell =>
                    'assets/hooks/teampilot-team-lead-delegate-only.ps1',
                },
              ),
        );
  }

  ExtensionProvisioner get _extensionProvisioner =>
      _cachedExtensionProvisioner ??= ExtensionProvisioner(
        manifests: _extensionManifests ?? builtInExtensionManifests(),
        isEnabled: (id) async => id == 'rtk' ? await _isRtkEnabled() : false,
        detector: _extensionDetector,
        hookProvisionerFor: _hookProvisionerForAsset,
      );

  ScriptFileHookProvisioner _hookProvisionerForAsset(String scriptAsset) {
    final host = _hostEnvironmentForProvision();
    switch (scriptAsset) {
      case 'rtk-rewrite':
        return _resolveRtkProvisioner(host);
      default:
        throw StateError('No hook provisioner for asset "$scriptAsset"');
    }
  }

  Future<void> _collectRtkWarnings(List<String> warnings) async {
    warnings.addAll(await _extensionProvisioner.collectWarnings());
  }

  Future<Map<String, Object?>> _maybeApplyRtk(
    Map<String, Object?> settings,
    String? memberToolDir,
  ) async {
    return _extensionProvisioner.applySettings(
      settings,
      memberToolDir?.trim() ?? '',
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

  Future<Map<String, Object?>> _maybeApplyTeamLeadHooks(
    Map<String, Object?> settings,
    TeamMemberConfig member,
    String memberToolDir, {
    required bool forceTeamLeadDelegateMode,
  }) async {
    if (!TeamMemberNaming.isTeamLead(member)) {
      return settings;
    }
    final host = _hostEnvironmentForProvision();
    final selfTargetProvisioner = _resolveTeamLeadHookProvisioner(host);
    final selfScriptPath = await selfTargetProvisioner.provision(memberToolDir);
    var merged = const TeamLeadSettingsMerge().mergeIntoSettings(
      base: settings,
      hookCommand: selfTargetProvisioner.commandForPath(selfScriptPath),
    );
    merged = const TeamLeadDelegateSettingsMerge().stripFromSettings(merged);
    if (forceTeamLeadDelegateMode) {
      final delegateProvisioner = _resolveTeamLeadDelegateHookProvisioner(host);
      final delegateScriptPath = await delegateProvisioner.provision(
        memberToolDir,
      );
      merged = const TeamLeadDelegateSettingsMerge().mergeIntoSettings(
        base: merged,
        hookCommand: delegateProvisioner.commandForPath(delegateScriptPath),
      );
    }
    return merged;
  }

  Future<String?> _resolveAppendSystemPromptPath({
    required LaunchProfileScope scope,
    required String tool,
    required TeamMemberConfig member,
  }) async {
    final path = MemberRoleProvision.rolePromptPath(
      sessionToolDir(scope.teamId, scope.sessionId, tool),
      member,
    );
    final stat = await _fs.stat(path);
    if (!stat.exists) return null;
    final raw = await _fs.readString(path);
    if (raw == null || raw.trim().isEmpty) return null;
    return path;
  }
}
