import 'package:path/path.dart' as p;

import '../../models/config_bundle.dart';
import '../../models/cli_preset.dart';
import '../../models/extension_manifest.dart';
import '../../models/skill.dart';
import '../../models/team_config.dart';
import '../team_bus/member_bus_idle_endpoint.dart';
import '../storage/runtime_layout.dart';
import '../extension/extension_detector.dart';
import '../host/host_execution_environment.dart';
import '../host/host_script_dialect.dart';
import '../host/script_file_hook_provisioner.dart';
import '../cli/registry/capabilities/config_profile_capability.dart';
import '../cli/registry/capabilities/plugin_provisioner_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../plugin/installed_plugin_catalog.dart';
import '../../repositories/workspace_project_config_repository.dart';
import '../io/filesystem.dart';
import '../cli/registry/mcp_writers/claude_project_mcp_cleanup.dart';
import '../mcp/mcp_registry_service.dart';
import '../resource/resource_provisioning_service.dart';
import '../resource/resource_scope.dart';
import '../launch/launch_manifest.dart';
import '../launch/launch_manifest_paths.dart';
import '../launch/manifest_executor.dart';
import '../launch/manifest_filesystem.dart';
import '../provider/workspace_trust_provisioner.dart';
import '../team/claude_team_roster_service.dart';
import 'cursor/cursor_workspace_warm_tier.dart';
import '../cli/registry/capabilities/cli_config_layout_capability.dart';
import '../cli/registry/capabilities/cli_session_lifecycle_capability.dart';
import '../storage/app_storage.dart';
import '../cli/preset_resolver.dart';
import 'config_profile_infrastructure.dart';

export '../cli/registry/config_profile/config_profile_context.dart';
export '../cli/registry/config_profile/config_profile_scope.dart';

Future<List<CliPreset>> _defaultLoadGlobalPresets() async => const [];

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
  static final _defaultCliRegistry = CliToolRegistry.builtIn();

  ConfigProfileService({
    required String basePath,
    String? home,
    Filesystem? fs,
    RuntimeLayout? layout,
    ConfigProfilePaths? catalog,
    Future<Set<String>> Function({String? teamId, String? workspaceId})?
    loadEnabledExtensionIds,
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
    Future<List<Skill>> Function()? loadInstalledSkills,
    Future<List<CliPreset>> Function() loadGlobalPresets =
        _defaultLoadGlobalPresets,
    WorkspaceProjectConfigRepository? projectConfigRepository,
  }) : _infra = ConfigProfileInfrastructure(
         basePath: basePath,
         home: home,
         layout:
             layout ??
             RuntimeLayout(teampilotRoot: basePath, fs: fs ?? AppStorage.fs),
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
       _catalogOverride = catalog,
       _cliRegistry = cliRegistry ?? _defaultCliRegistry,
       _loadInstalledSkills = loadInstalledSkills,
       _loadGlobalPresets = loadGlobalPresets,
       _projectConfigRepository = projectConfigRepository;

  ConfigProfileService._fromInfrastructure({
    required ConfigProfileInfrastructure infra,
    ConfigProfilePaths? catalog,
    CliToolRegistry? cliRegistry,
    Future<List<Skill>> Function()? loadInstalledSkills,
    Future<List<CliPreset>> Function() loadGlobalPresets =
        _defaultLoadGlobalPresets,
    WorkspaceProjectConfigRepository? projectConfigRepository,
  }) : _infra = infra,
       _catalogOverride = catalog,
       _cliRegistry = cliRegistry ?? _defaultCliRegistry,
       _loadInstalledSkills = loadInstalledSkills,
       _loadGlobalPresets = loadGlobalPresets,
       _projectConfigRepository = projectConfigRepository;

  final ConfigProfileInfrastructure _infra;
  final ConfigProfilePaths? _catalogOverride;
  final CliToolRegistry _cliRegistry;
  final Future<List<Skill>> Function()? _loadInstalledSkills;
  final Future<List<CliPreset>> Function() _loadGlobalPresets;
  final WorkspaceProjectConfigRepository? _projectConfigRepository;

  /// Control-plane paths for provider catalog reads (home when work != home).
  ConfigProfilePaths get catalog => _catalogOverride ?? _infra;

  Future<ResourceCatalog> _skillCatalog() async {
    final skills =
        await (_loadInstalledSkills?.call() ?? Future.value(const <Skill>[]));
    return ResourceCatalog(
      skills: skills,
      skillsRoot: AppPaths.skillsDirForTeampilotRoot(catalog.basePath),
      pathContext: fs.pathContext,
    );
  }

  ConfigProfileService _stagingService({
    required Filesystem stagingFs,
    required String workTeampilotRoot,
  }) {
    final layout = RuntimeLayout(
      teampilotRoot: workTeampilotRoot,
      fs: stagingFs,
    );
    return ConfigProfileService._fromInfrastructure(
      infra: _infra.rebindFilesystem(fs: stagingFs, layout: layout),
      catalog: catalog,
      cliRegistry: _cliRegistry,
      loadInstalledSkills: _loadInstalledSkills,
      loadGlobalPresets: _loadGlobalPresets,
      projectConfigRepository: _projectConfigRepository,
    );
  }

  Future<
    ({TeamMemberConfig? member, List<TeamMemberConfig> members, CliTool cli})
  >
  _resolveTeamLaunchRoster({
    required TeamProfile? team,
    required TeamMemberConfig? member,
    required List<TeamMemberConfig> members,
    required CliTool cli,
  }) async {
    if (team == null) {
      return (member: member, members: members, cli: cli);
    }
    final presets = await _loadGlobalPresets();
    final roster = members.isNotEmpty ? members : team.members;
    final resolvedMember = member != null && member.isValid
        ? memberForLaunch(team: team, member: member, globalPresets: presets)
        : member;
    final resolvedRoster = resolveTeamRosterForLaunch(
      team: team,
      members: roster,
      globalPresets: presets,
    );
    final effectiveCli = resolvedMember != null && resolvedMember.isValid
        ? (team.teamMode == TeamMode.mixed
              ? resolvedMember.cli ?? team.cli
              : team.cli)
        : cli;
    return (member: resolvedMember, members: resolvedRoster, cli: effectiveCli);
  }

  @override
  String get basePath => _infra.basePath;

  @override
  String get home => _infra.home;

  @override
  RuntimeLayout get layout => _infra.layout;

  @override
  Filesystem get fs => _infra.fs;

  @override
  p.Context get pathContext => _infra.pathContext;

  String get cliDefaultsDir => layout.cliDefaultsDir;

  String get identitiesRuntimeDir => layout.identitiesRuntimeDir;

  String teamScopeDir(String teamId) => layout.identityRuntimeDir(teamId);

  String workspaceConfigDir(String workspaceId) =>
      layout.workspace.workspaceConfigDir(workspaceId);

  String sessionRuntimeToolDir(
    String workspaceId,
    String sessionId,
    String tool,
  ) => layout.sessionRuntimeToolDir(workspaceId, sessionId, tool);

  @override
  String sessionToolDir(
    String workspaceId,
    String sessionId,
    String tool, {
    String? memberId,
  }) => _infra.sessionToolDir(
    workspaceId,
    sessionId,
    tool,
    memberId: memberId,
  );

  String _launchResourceConfigDir({
    required CliTool cli,
    required String workspaceId,
    required String sessionId,
    String? memberId,
    TeamProfile? team,
  }) {
    if (CursorWorkspaceWarmTier.applies(team: team, cli: cli)) {
      return CursorWorkspaceWarmTier.sharedRoot(
        layout,
        workspaceId,
        team!.id,
      );
    }
    return sessionConfigDirForTool(
      cli,
      layout,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: memberId,
      teamId: team?.id,
    );
  }

  Future<void> ensureTeamProfile(
    String teamId, {
    CliTool cli = CliTool.claude,
  }) async {
    final trimmed = teamId.trim();
    if (trimmed.isEmpty) return;
    await fs.ensureDir(teamScopeDir(trimmed));
  }

  Future<void> ensureSessionProfile(
    String workspaceId,
    String sessionId,
    String teamId, {
    CliTool cli = CliTool.claude,
    TeamProfile? team,
    ConfigBundle? runtimeBundle,
    String? memberId,
    Map<String, Map<String, Object?>>? extraMcpServers,
    Iterable<String> projectMcpRoots = const [],
    String workingDirectory = '',
    MemberBusIdleEndpoint? busIdle,
  }) async {
    final trimmedWorkspaceId = effectiveLaunchWorkspaceId(
      workspaceId: workspaceId,
      teamId: teamId,
    );
    final trimmedSessionId = sessionId.trim();
    final trimmedTeamId = teamId.trim();
    if (trimmedWorkspaceId.isEmpty ||
        trimmedSessionId.isEmpty ||
        trimmedTeamId.isEmpty) {
      return;
    }

    await ensureTeamProfile(trimmedTeamId, cli: cli);
    String? memberProvisionJson;
    await Future.wait([
      layout.ensureSessionRuntimeInheritsIdentity(
        trimmedWorkspaceId,
        trimmedSessionId,
        trimmedTeamId,
        cli.value,
        memberId: memberId,
      ),
      layout
          .provisionSessionPluginsFromIdentity(
            trimmedWorkspaceId,
            trimmedSessionId,
            trimmedTeamId,
            cli.value,
            memberId: memberId,
          )
          .then((json) => memberProvisionJson = json),
    ]);
    final pluginProvisioner = _cliRegistry
        .capability<PluginProvisionerCapability>(cli);
    final warmTier = CursorWorkspaceWarmTier.applies(team: team, cli: cli);
    if (pluginProvisioner != null) {
      final enabledPlugins =
          runtimeBundle?.pluginIds ?? const <String>[];
      await pluginProvisioner.provision(
        PluginProvisionContext(
          fs: fs,
          teampilotRoot: basePath,
          configDir: _launchResourceConfigDir(
            cli: cli,
            workspaceId: trimmedWorkspaceId,
            sessionId: trimmedSessionId,
            memberId: memberId,
            team: team,
          ),
          bundlePoolDir: layout.sessionRuntimePluginsDir(
            trimmedWorkspaceId,
            trimmedSessionId,
            cli.value,
            memberId: memberId,
          ),
          enabledPluginIds: enabledPlugins,
          installedCatalog: await InstalledPluginCatalog.load(fs, basePath),
          layout: layout,
          tool: cli,
          memberProvisionJson: memberProvisionJson,
          mcpConfigFileName: warmTier
              ? CursorWorkspaceWarmTier.mcpBaseFileName
              : null,
        ),
      );
    }
    final cap = _cliRegistry.capability<ConfigProfileCapability>(cli);
    if (cap != null) {
      await cap.ensureSessionProfile(
        ConfigProfileSessionContext(
          workspaceId: trimmedWorkspaceId,
          teamId: trimmedTeamId,
          sessionId: trimmedSessionId,
          members: team?.members ?? const [],
          paths: this,
          team: team,
          memberId: memberId,
        ),
      );
    }
    await _cliRegistry.lifecycleFor(cli).ensurePersisted(
      CliSessionPersistContext(
        workspaceId: trimmedWorkspaceId,
        sessionId: trimmedSessionId,
        memberId: memberId,
        tool: cli,
        paths: this,
        team: team,
        busIdle: busIdle,
        workingDirectory: workingDirectory,
      ),
    );
    final mcpRegistry = McpRegistryService(fs: fs, layout: layout);
    if (warmTier) {
      await mcpRegistry.writeCursorWorkspaceMcpBase(
        workspaceId: trimmedWorkspaceId,
        teamId: trimmedTeamId,
        extraServers: extraMcpServers,
        projectMcpRoots: projectMcpRoots,
      );
      final trimmedMemberId = memberId?.trim() ?? '';
      if (trimmedMemberId.isNotEmpty) {
        await mcpRegistry.mergeCursorMemberMcpCredentials(
          workspaceId: trimmedWorkspaceId,
          sessionId: trimmedSessionId,
          teamId: trimmedTeamId,
          memberId: trimmedMemberId,
        );
      }
    } else {
      await mcpRegistry.writeForSession(
        workspaceId: trimmedWorkspaceId,
        teamId: trimmedTeamId,
        sessionId: trimmedSessionId,
        memberId: memberId,
        extraServers: extraMcpServers,
        projectMcpRoots: projectMcpRoots,
      );
    }
  }

  Future<void> ensureWorkspaceProfile(
    String workspaceId, {
    CliTool cli = CliTool.claude,
  }) async {
    final trimmed = workspaceId.trim();
    if (trimmed.isEmpty) return;
    await layout.ensureWorkspaceConfigInheritsApp(trimmed, cli.value);
  }

  /// Phase A: workspace-level profile on the work machine (not per-session).
  ///
  /// Simple mode skips `identities-runtime/` — only workspace inherit + trust.
  Future<void> provisionWorkspace({
    required String workspaceId,
    required CliTool cli,
    Iterable<String> trustedDirectories = const [],
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    if (trimmedWorkspaceId.isEmpty) return;

    await ensureWorkspaceProfile(trimmedWorkspaceId, cli: cli);

    final paths = [
      for (final directory in trustedDirectories)
        if (directory.trim().isNotEmpty) directory.trim(),
    ];
    if (paths.isNotEmpty) {
      await WorkspaceTrustProvisioner(
        layout: layout,
        fs: fs,
      ).provisionWorkspace(
        workspaceId: trimmedWorkspaceId,
        directories: paths,
        tools: [cli.value],
      );
    }
  }

  /// Phase B (work fs) for Simple: cli-defaults → workspace → session only.
  ///
  /// [runtimeBundle] is the sole skills/plugins/MCP id source (already merged).
  Future<List<String>> applySimpleSessionFilesystem({
    required String workspaceId,
    required String sessionId,
    required ConfigBundle runtimeBundle,
    CliTool cli = CliTool.claude,
    Map<String, Map<String, Object?>>? extraMcpServers,
    Iterable<String> projectMcpRoots = const [],
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedWorkspaceId.isEmpty || trimmedSessionId.isEmpty) {
      return const [];
    }

    final warnings = <String>[];
    await layout.ensureSessionRuntimeInheritsWorkspace(
      trimmedWorkspaceId,
      trimmedSessionId,
      cli.value,
    );

    final pluginProvisioner = _cliRegistry
        .capability<PluginProvisionerCapability>(cli);
    if (pluginProvisioner != null) {
      await pluginProvisioner.provision(
        PluginProvisionContext(
          fs: fs,
          teampilotRoot: basePath,
          configDir: _launchResourceConfigDir(
            cli: cli,
            workspaceId: trimmedWorkspaceId,
            sessionId: trimmedSessionId,
          ),
          bundlePoolDir: layout.sessionRuntimePluginsDir(
            trimmedWorkspaceId,
            trimmedSessionId,
            cli.value,
          ),
          enabledPluginIds: runtimeBundle.pluginIds,
          installedCatalog: await InstalledPluginCatalog.load(fs, basePath),
          layout: layout,
          tool: cli,
        ),
      );
    }

    final provisionResult =
        await ResourceProvisioningService(
          fs: fs,
          registry: _cliRegistry,
        ).provisionForLaunch(
          scope: SimpleResourceScope(bundle: runtimeBundle),
          cli: cli,
          configDir: _launchResourceConfigDir(
            cli: cli,
            workspaceId: trimmedWorkspaceId,
            sessionId: trimmedSessionId,
          ),
          catalog: await _skillCatalog(),
        );
    warnings.addAll(provisionResult.warnings);

    await McpRegistryService(
      fs: fs,
      layout: layout,
    ).writeForSimpleSession(
      workspaceId: trimmedWorkspaceId,
      sessionId: trimmedSessionId,
      mcpServerIds: runtimeBundle.mcpServerIds,
      extraServers: extraMcpServers,
      projectMcpRoots: projectMcpRoots,
    );

    return warnings;
  }

  /// Phase B (control plane): session config JSON + env from CLI capabilities.
  ///
  /// [member] comes from [SessionRuntimePlan.member] (expert pack persona).
  Future<TeamLaunchOutcome> contributeSimpleSessionLaunch({
    required String workspaceId,
    required String sessionId,
    required TeamMemberConfig member,
    String workingDirectory = '',
    List<String> additionalDirectories = const [],
    MemberBusIdleEndpoint? busIdle,
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedWorkspaceId.isEmpty || trimmedSessionId.isEmpty) {
      return const TeamLaunchOutcome(environment: {});
    }

    final warnings = <String>[];
    final cli = member.cli ?? CliTool.claude;
    // Path keys only — Simple has no team identity; teamId mirrors workspaceId
    // so sessionToolDir / append-prompt helpers keep a stable scope.
    final scope = LaunchProfileScope(
      workspaceId: trimmedWorkspaceId,
      teamId: trimmedWorkspaceId,
      sessionId: trimmedSessionId,
      cliTeamName: trimmedSessionId,
    );

    final cap = _cliRegistry.capability<ConfigProfileCapability>(cli);
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
          workspaceId: trimmedWorkspaceId,
          teamId: '',
          sessionId: trimmedSessionId,
          scope: scope,
          team: null,
          member: member,
          members: [member],
          workingDirectory: workingDirectory,
          additionalDirectories: additionalDirectories,
          paths: this,
          catalog: catalog,
          busIdle: busIdle,
        ),
      );
    } on Object catch (e) {
      return TeamLaunchOutcome(
        environment: const {},
        warnings: [...warnings, 'config_profile_${cli.value}: $e'],
      );
    }

    return TeamLaunchOutcome(
      environment: contribution.environment,
      warnings: [...warnings, ...contribution.warnings],
    );
  }

  /// Stages Simple session launch mutations into [LaunchManifest].
  Future<({TeamLaunchOutcome outcome, LaunchManifest manifest})>
  stageSimpleSessionLaunch({
    required Filesystem readDelegate,
    required String workTeampilotRoot,
    required String workspaceId,
    required String sessionId,
    required ConfigBundle runtimeBundle,
    required TeamMemberConfig member,
    String workingDirectory = '',
    List<String> additionalDirectories = const [],
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
  }) async {
    final manifestCtx = workPathContextFor(
      readDelegate: readDelegate,
      workTeampilotRoot: workTeampilotRoot,
    );
    final manifest = LaunchManifest(pathContext: manifestCtx);
    final stagingFs = ManifestFilesystem(
      manifest: manifest,
      readDelegate: readDelegate,
      pathContext: manifestCtx,
    );
    final staging = _stagingService(
      stagingFs: stagingFs,
      workTeampilotRoot: workTeampilotRoot,
    );

    final cli = member.cli ?? CliTool.claude;
    final fsWarnings = await staging.applySimpleSessionFilesystem(
      workspaceId: workspaceId,
      sessionId: sessionId,
      runtimeBundle: runtimeBundle,
      cli: cli,
      extraMcpServers: extraMcpServers,
      projectMcpRoots: projectMcpRootsFromLaunch(
        workingDirectory: workingDirectory,
        additionalDirectories: additionalDirectories,
      ),
    );
    final outcome = await staging.contributeSimpleSessionLaunch(
      workspaceId: workspaceId,
      sessionId: sessionId,
      member: member,
      workingDirectory: workingDirectory,
      additionalDirectories: additionalDirectories,
      busIdle: busIdle,
    );
    return (
      outcome: TeamLaunchOutcome(
        environment: outcome.environment,
        warnings: [...fsWarnings, ...outcome.warnings],
      ),
      manifest: manifest,
    );
  }

  /// Phase B: full Simple session launch — stage then flush to [fs].
  Future<TeamLaunchOutcome> prepareSimpleSessionLaunch({
    required String workspaceId,
    required String sessionId,
    required ConfigBundle runtimeBundle,
    required TeamMemberConfig member,
    String workingDirectory = '',
    List<String> additionalDirectories = const [],
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
    ManifestExecutor? manifestExecutor,
  }) async {
    final staged = await stageSimpleSessionLaunch(
      readDelegate: fs,
      workTeampilotRoot: basePath,
      workspaceId: workspaceId,
      sessionId: sessionId,
      runtimeBundle: runtimeBundle,
      member: member,
      workingDirectory: workingDirectory,
      additionalDirectories: additionalDirectories,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
    );
    final executor = manifestExecutor ?? const ManifestExecutor();
    await executor.flush(manifest: staged.manifest, targetFs: fs, sourceFs: fs);
    return staged.outcome;
  }

  /// Stages team launch mutations into [LaunchManifest] without touching the
  /// work filesystem. [readDelegate] supplies catalog reads (home or work).
  Future<({TeamLaunchOutcome outcome, LaunchManifest manifest})>
  stageTeamLaunch({
    required Filesystem readDelegate,
    required String workTeampilotRoot,
    required String workspaceId,
    required String sessionId,
    required String teamId,
    String cliTeamName = '',
    CliTool cli = CliTool.claude,
    List<TeamMemberConfig> members = const [],
    TeamMemberConfig? member,
    String workingDirectory = '',
    List<String> additionalDirectories = const [],
    TeamProfile? team,
    required ConfigBundle runtimeBundle,
    String? leadSessionId,
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
  }) async {
    final trimmedWorkspaceId = effectiveLaunchWorkspaceId(
      workspaceId: workspaceId,
      teamId: teamId,
    );
    final trimmedSessionId = sessionId.trim();
    final trimmedTeamId = teamId.trim();
    if (trimmedWorkspaceId.isEmpty ||
        trimmedSessionId.isEmpty ||
        trimmedTeamId.isEmpty) {
      return (
        outcome: const TeamLaunchOutcome(environment: {}),
        manifest: LaunchManifest(pathContext: readDelegate.pathContext),
      );
    }

    final warnings = <String>[];
    await _infra.collectExtensionWarnings(warnings, teamId: trimmedTeamId);

    final resolvedRoster = await _resolveTeamLaunchRoster(
      team: team,
      member: member,
      members: members,
      cli: cli,
    );
    final launchMember = resolvedRoster.member;
    final launchMembers = resolvedRoster.members;
    final launchCli = resolvedRoster.cli;

    String? memberId;
    if (team?.teamMode == TeamMode.mixed &&
        launchMember != null &&
        launchMember.isValid) {
      memberId = ClaudeTeamRosterService.safeClaudePathSegment(launchMember.id);
    }

    final scope = resolveLaunchProfileScope(
      workspaceId: trimmedWorkspaceId,
      teamId: trimmedTeamId,
      appSessionId: trimmedSessionId,
      cliTeamName: cliTeamName,
      memberId: memberId,
    );

    final manifestCtx = workPathContextFor(
      readDelegate: readDelegate,
      workTeampilotRoot: workTeampilotRoot,
    );
    final manifest = LaunchManifest(pathContext: manifestCtx);
    final stagingFs = ManifestFilesystem(
      manifest: manifest,
      readDelegate: readDelegate,
      pathContext: manifestCtx,
    );
    final staging = _stagingService(
      stagingFs: stagingFs,
      workTeampilotRoot: workTeampilotRoot,
    );

    await staging.ensureSessionProfile(
      trimmedWorkspaceId,
      trimmedSessionId,
      trimmedTeamId,
      cli: launchCli,
      team: team,
      runtimeBundle: runtimeBundle,
      memberId: memberId,
      extraMcpServers: extraMcpServers,
      projectMcpRoots: projectMcpRootsFromLaunch(
        workingDirectory: workingDirectory,
        additionalDirectories: additionalDirectories,
      ),
      workingDirectory: workingDirectory,
      busIdle: busIdle,
    );

    if (team != null) {
      final provisionResult =
          await ResourceProvisioningService(
            fs: stagingFs,
            registry: _cliRegistry,
          ).provisionForLaunch(
            scope: WorkspaceResourceScope(bundle: runtimeBundle),
            cli: launchCli,
            configDir: staging._launchResourceConfigDir(
              cli: launchCli,
              workspaceId: trimmedWorkspaceId,
              sessionId: trimmedSessionId,
              memberId: memberId,
              team: team,
            ),
            catalog: await _skillCatalog(),
          );
      warnings.addAll(provisionResult.warnings);
    }

    final cap = _cliRegistry.capability<ConfigProfileCapability>(launchCli);
    if (cap == null) {
      return (
        outcome: TeamLaunchOutcome(
          environment: const {},
          warnings: [...warnings, 'unknown_cli_${launchCli.value}'],
        ),
        manifest: manifest,
      );
    }

    ConfigProfileLaunchContribution contribution;
    try {
      contribution = await cap.contributeLaunch(
        ConfigProfileLaunchContext(
          workspaceId: trimmedWorkspaceId,
          teamId: scope.teamId,
          sessionId: scope.sessionId,
          scope: scope,
          team: team,
          member: launchMember,
          members: launchMembers,
          workingDirectory: workingDirectory,
          additionalDirectories: additionalDirectories,
          paths: staging,
          catalog: catalog,
          leadSessionId: leadSessionId,
          busIdle: busIdle,
          memberId: memberId,
        ),
      );
    } on Object catch (e) {
      return (
        outcome: TeamLaunchOutcome(
          environment: const {},
          warnings: [...warnings, 'config_profile_${launchCli.value}: $e'],
        ),
        manifest: manifest,
      );
    }

    return (
      outcome: TeamLaunchOutcome(
        environment: contribution.environment,
        warnings: [...warnings, ...contribution.warnings],
      ),
      manifest: manifest,
    );
  }

  Future<TeamLaunchOutcome> prepareTeamLaunch({
    required String workspaceId,
    required String sessionId,
    required String teamId,
    String cliTeamName = '',
    CliTool cli = CliTool.claude,
    List<TeamMemberConfig> members = const [],
    TeamMemberConfig? member,
    String workingDirectory = '',
    List<String> additionalDirectories = const [],
    TeamProfile? team,
    required ConfigBundle runtimeBundle,
    String? leadSessionId,
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
    ManifestExecutor? manifestExecutor,
  }) async {
    final staged = await stageTeamLaunch(
      readDelegate: fs,
      workTeampilotRoot: basePath,
      workspaceId: workspaceId,
      sessionId: sessionId,
      teamId: teamId,
      cliTeamName: cliTeamName,
      cli: cli,
      members: members,
      member: member,
      workingDirectory: workingDirectory,
      additionalDirectories: additionalDirectories,
      team: team,
      runtimeBundle: runtimeBundle,
      leadSessionId: leadSessionId,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
    );
    final executor = manifestExecutor ?? const ManifestExecutor();
    await executor.flush(manifest: staged.manifest, targetFs: fs, sourceFs: fs);
    return staged.outcome;
  }

  @override
  Future<Map<String, Object?>> readMetadataFile(
    String path,
    Map<String, Object?> defaults,
  ) => _infra.readMetadataFile(path, defaults);

  @override
  Future<void> writeJsonIfChanged(String path, Map<String, Object?> value) =>
      _infra.writeJsonIfChanged(path, value);

  @override
  Future<Map<String, Object?>> metadataWithTrustedProjects({
    required String metadataPath,
    required Map<String, Object?> defaultMetadata,
    required Map<String, Object?> defaultProjectConfig,
    required Iterable<String> directories,
  }) => _infra.metadataWithTrustedProjects(
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
  }) => _infra.trustedProjectsAlreadyCurrent(
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
    String? workspaceId,
  }) => _infra.writeSettingsFile(
    path,
    settings,
    memberToolDir: memberToolDir,
    tool: tool,
    teamId: teamId,
    workspaceId: workspaceId,
  );

  @override
  Future<bool> hasEnabledExtensionSettingsHooks(
    String tool, {
    String? teamId,
    String? workspaceId,
  }) => _infra.hasEnabledExtensionSettingsHooks(
    tool,
    teamId: teamId,
    workspaceId: workspaceId,
  );

  @override
  Future<Map<String, Object?>> applyExtensionSettings(
    Map<String, Object?> settings,
    String? memberToolDir, {
    required String tool,
    String? teamId,
    String? workspaceId,
  }) => _infra.applyExtensionSettings(
    settings,
    memberToolDir,
    tool: tool,
    teamId: teamId,
    workspaceId: workspaceId,
  );

  @override
  Future<Map<String, Object?>> maybeApplyTeamLeadHooks(
    Map<String, Object?> settings,
    TeamMemberConfig member,
    String memberToolDir, {
    required bool forceTeamLeadDelegateMode,
  }) => _infra.maybeApplyTeamLeadHooks(
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
  }) => _infra.resolveAppendSystemPromptPath(
    scope: scope,
    tool: tool,
    member: member,
  );

  @override
  HostExecutionEnvironment hostEnvironmentForProvision() =>
      _infra.hostEnvironmentForProvision();
}
