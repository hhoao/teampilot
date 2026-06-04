import 'package:path/path.dart' as p;

import '../../models/extension_manifest.dart';
import '../../models/team_config.dart';
import '../cli/cli_data_layout.dart';
import '../extension/extension_detector.dart';
import '../host/host_execution_environment.dart';
import '../host/host_script_dialect.dart';
import '../host/script_file_hook_provisioner.dart';
import '../cli/registry/built_in_cli_tools.dart';
import '../cli/registry/capabilities/config_profile_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../io/filesystem.dart';
import '../mcp/mcp_registry_service.dart';
import '../plugin/cli_plugin_registry_service.dart';
import '../storage/app_storage.dart';
import 'config_profile_infrastructure.dart';

export '../cli/registry/config_profile/config_profile_context.dart';
export '../cli/registry/config_profile/config_profile_scope.dart';

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

/// Orchestrates config-profile layout, MCP/plugin merge, and per-CLI capabilities.
class ConfigProfileService implements ConfigProfileDelegate {
  static final _defaultCliRegistry = () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    return registry;
  }();

  static const _pluginRegistryCliIds = {'flashskyai', 'claude'};

  ConfigProfileService({
    required String basePath,
    Filesystem? fs,
    CliDataLayout? layout,
    Future<Set<String>> Function({String? teamId})? loadEnabledExtensionIds,
    ExtensionDetector? extensionDetector,
    List<ExtensionManifest>? extensionManifests,
    Map<String, ScriptFileHookProvisioner>? extensionHookProvisioners,
    ScriptFileHookProvisioner? teamLeadHookProvisioner,
    Future<String> Function(HostScriptDialect dialect)? loadTeamLeadHookScript,
    ScriptFileHookProvisioner? teamLeadDelegateHookProvisioner,
    Future<String> Function(HostScriptDialect dialect)?
    loadTeamLeadDelegateHookScript,
    HostExecutionEnvironment? hostEnvironment,
    CliToolRegistry? cliRegistry,
  }) : _infra = ConfigProfileInfrastructure(
         basePath: basePath,
         layout:
             layout ??
             CliDataLayout(teampilotRoot: basePath, fs: fs ?? AppStorage.fs),
         fs: fs,
         loadEnabledExtensionIds: loadEnabledExtensionIds,
         extensionDetector: extensionDetector,
         extensionManifests: extensionManifests,
         extensionHookProvisioners: extensionHookProvisioners,
         teamLeadHookProvisioner: teamLeadHookProvisioner,
         loadTeamLeadHookScript: loadTeamLeadHookScript,
         teamLeadDelegateHookProvisioner: teamLeadDelegateHookProvisioner,
         loadTeamLeadDelegateHookScript: loadTeamLeadDelegateHookScript,
         hostEnvironment: hostEnvironment,
       ),
       _cliRegistry = cliRegistry ?? _defaultCliRegistry;

  final ConfigProfileInfrastructure _infra;
  final CliToolRegistry _cliRegistry;

  @override
  String get basePath => _infra.basePath;

  @override
  CliDataLayout get layout => _infra.layout;

  @override
  Filesystem get fs => _infra.fs;

  @override
  p.Context get pathContext => _infra.pathContext;

  String get configProfilesDir => layout.configProfilesDir;

  String teamScopeDir(String teamId) =>
      pathContext.join(configProfilesDir, 'teams', teamId.trim());

  String sessionProfileDir(String teamId, String sessionId) =>
      pathContext.join(teamScopeDir(teamId), 'members', sessionId.trim());

  @override
  String sessionToolDir(String teamId, String sessionId, String tool) =>
      _infra.sessionToolDir(teamId, sessionId, tool);

  Future<void> ensureTeamProfile(
    String teamId, {
    TeamCli cli = TeamCli.flashskyai,
  }) async {
    final trimmed = teamId.trim();
    if (trimmed.isEmpty) return;
    await fs.ensureDir(teamScopeDir(trimmed));
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
        fs: fs,
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
    await McpRegistryService(fs: fs, layout: layout).writeForSession(
      teamId: trimmedTeamId,
      sessionId: trimmedSessionId,
      extraServers: extraMcpServers,
    );
  }

  Future<TeamLaunchOutcome> prepareTeamLaunch({
    required String teamId,
    String runtimeTeamId = '',
    TeamCli cli = TeamCli.flashskyai,
    List<TeamMemberConfig> members = const [],
    TeamMemberConfig? member,
    String workingDirectory = '',
    List<String> additionalDirectories = const [],
    TeamConfig? team,
    String? leadSessionId,
    Map<String, Map<String, Object?>>? extraMcpServers,
    String? busIdleUrl,
  }) async {
    final trimmedTeamId = teamId.trim();
    if (trimmedTeamId.isEmpty) {
      return const TeamLaunchOutcome(environment: {});
    }

    final warnings = <String>[];
    await _infra.collectExtensionWarnings(
      warnings,
      teamId: trimmedTeamId,
    );

    var scope = resolveLaunchProfileScope(
      teamId: trimmedTeamId,
      runtimeTeamId: runtimeTeamId,
    );
    if (team?.teamMode == TeamMode.mixed && member != null && member.isValid) {
      scope = LaunchProfileScope(
        teamId: scope.teamId,
        sessionId: mixedModeMemberScopeSessionId(
          pathContext,
          scope.sessionId,
          member,
        ),
        cliTeamName: scope.cliTeamName,
      );
    }

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
          leadSessionId: leadSessionId,
          busIdleUrl: busIdleUrl,
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

  @override
  Future<Map<String, Object?>> readMetadataFile(
    String path,
    Map<String, Object?> defaults,
  ) =>
      _infra.readMetadataFile(path, defaults);

  @override
  Future<void> writeJsonIfChanged(String path, Map<String, Object?> value) =>
      _infra.writeJsonIfChanged(path, value);

  @override
  Future<Map<String, Object?>> metadataWithTrustedProjects({
    required String metadataPath,
    required Map<String, Object?> defaultMetadata,
    required Map<String, Object?> defaultProjectConfig,
    required Iterable<String> directories,
  }) =>
      _infra.metadataWithTrustedProjects(
        metadataPath: metadataPath,
        defaultMetadata: defaultMetadata,
        defaultProjectConfig: defaultProjectConfig,
        directories: directories,
      );

  @override
  Future<bool> trustedProjectsAlreadyCurrent(
    String metadataPath,
    Iterable<String> directories, {
    required Map<String, Object?> defaultMetadata,
  }) =>
      _infra.trustedProjectsAlreadyCurrent(
        metadataPath,
        directories,
        defaultMetadata: defaultMetadata,
      );

  @override
  Future<Map<String, Object?>> readSettingsFile(String path) =>
      _infra.readSettingsFile(path);

  @override
  Future<void> writeSettingsFile(
    String path,
    Map<String, Object?> settings, {
    String? memberToolDir,
    required String tool,
    String? teamId,
  }) =>
      _infra.writeSettingsFile(
        path,
        settings,
        memberToolDir: memberToolDir,
        tool: tool,
        teamId: teamId,
      );

  @override
  Future<bool> hasEnabledExtensionSettingsHooks(
    String tool, {
    String? teamId,
  }) =>
      _infra.hasEnabledExtensionSettingsHooks(tool, teamId: teamId);

  @override
  Future<Map<String, Object?>> applyExtensionSettings(
    Map<String, Object?> settings,
    String? memberToolDir, {
    required String tool,
    String? teamId,
  }) =>
      _infra.applyExtensionSettings(
        settings,
        memberToolDir,
        tool: tool,
        teamId: teamId,
      );

  @override
  Future<Map<String, Object?>> maybeApplyTeamLeadHooks(
    Map<String, Object?> settings,
    TeamMemberConfig member,
    String memberToolDir, {
    required bool forceTeamLeadDelegateMode,
  }) =>
      _infra.maybeApplyTeamLeadHooks(
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
      _infra.resolveAppendSystemPromptPath(
        scope: scope,
        tool: tool,
        member: member,
      );

  @override
  HostExecutionEnvironment hostEnvironmentForProvision() =>
      _infra.hostEnvironmentForProvision();
}
