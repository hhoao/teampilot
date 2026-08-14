import 'package:path/path.dart' as p;

import '../../models/config_bundle.dart';
import '../../models/cli_preset.dart';
import '../../models/extension_manifest.dart';
import '../../models/hook_entry.dart';
import '../../models/plugin.dart';
import '../../models/skill.dart';
import '../../models/team_config.dart';
import '../../utils/logging/logger.dart';
import '../team_bus/member_bus_idle_endpoint.dart';
import '../agent_status/member_agent_status_endpoint.dart';
import '../storage/runtime_layout.dart';
import '../extension/extension_detector.dart';
import '../extension/extension_provisioner.dart';
import '../host/host_execution_environment.dart';
import '../host/host_script_dialect.dart';
import '../host/script_file_hook_provisioner.dart';
import '../cli/registry/capabilities/plugin_capability.dart';
import '../cli/registry/capabilities/provider_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../plugin/installed_plugin_catalog.dart';
import '../plugin/marketplace_shared_store.dart';
import '../plugin/plugin_bundle_pool_service.dart';
import '../../repositories/workspace_project_config_repository.dart';
import '../io/filesystem.dart';
import '../cli/claude/capabilities/mcp_project_cleanup.dart';
import '../mcp/mcp_registry_service.dart';
import '../resource/resource_provisioning_service.dart';
import '../resource/resource_scope.dart';
import '../launch/launch_manifest.dart';
import '../launch/launch_manifest_paths.dart';
import '../launch/manifest_executor.dart';
import '../launch/manifest_filesystem.dart';
import '../provider/workspace_trust_provisioner.dart';
import '../cli/claude/team_roster_service.dart';
import '../cli/cursor/provider/cursor_workspace_warm_tier.dart';
import '../cli/registry/capabilities/cli_session_capability.dart';
import '../storage/app_storage.dart';
import '../cli/preset_resolver.dart';
import '../hook/hook_library_resolver.dart';
import '../cli/registry/config_profile/config_profile_context.dart';
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
    // Ensure the seat being launched is present for per-member settings /
    // official credential linking (callers may pass only `member`).
    final launchMembers = <TeamMemberConfig>[...resolvedRoster];
    if (resolvedMember != null && resolvedMember.isValid) {
      final index = launchMembers.indexWhere((m) => m.id == resolvedMember.id);
      if (index >= 0) {
        launchMembers[index] = resolvedMember;
      } else {
        launchMembers.add(resolvedMember);
      }
    }
    final effectiveCli = resolvedMember != null && resolvedMember.isValid
        ? (team.teamMode == TeamMode.mixed
              ? resolvedMember.cli ?? team.cli
              : team.cli)
        : cli;
    return (member: resolvedMember, members: launchMembers, cli: effectiveCli);
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

  Future<List<String>> ensureSessionProfile(
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
    final warnings = <String>[];
    final trimmedWorkspaceId = effectiveLaunchWorkspaceId(
      workspaceId: workspaceId,
      teamId: teamId,
    );
    final trimmedSessionId = sessionId.trim();
    final trimmedTeamId = teamId.trim();
    if (trimmedWorkspaceId.isEmpty ||
        trimmedSessionId.isEmpty ||
        trimmedTeamId.isEmpty) {
      return warnings;
    }

    await ensureTeamProfile(trimmedTeamId, cli: cli);
    await layout.ensureSessionRuntimeInheritsIdentity(
      trimmedWorkspaceId,
      trimmedSessionId,
      trimmedTeamId,
      cli.value,
      memberId: memberId,
    );
    final configDir = _launchResourceConfigDir(
      cli: cli,
      workspaceId: trimmedWorkspaceId,
      sessionId: trimmedSessionId,
      memberId: memberId,
      team: team,
    );
    // Share the persisted marketplace clone into this session's CONFIG_DIR so
    // the CLI reuses one per-tool flavor dir instead of cloning per session.
    await MarketplaceSharedStore(fs: fs, teampilotRoot: basePath)
        .ensureSessionMarketplacesLinked(configDir: configDir, tool: cli);
    final pluginProvisioner = _cliRegistry
        .capability<PluginCapability>(cli);
    final warmTier = CursorWorkspaceWarmTier.applies(team: team, cli: cli);
    if (pluginProvisioner != null) {
      final installedCatalog = await InstalledPluginCatalog.load(fs, basePath);
      final enabledPlugins = runtimeBundle?.pluginIds ?? const <String>[];
      final poolResult = await PluginBundlePoolService(
        fs: fs,
        teampilotRoot: basePath,
      ).reconcile(
        poolDir: layout.sessionRuntimePluginsDir(
          trimmedWorkspaceId,
          trimmedSessionId,
          cli.value,
          memberId: memberId,
        ),
        enabledPluginIds: enabledPlugins,
        installedCatalog: installedCatalog,
        paths: pluginProvisioner.manifestPaths ?? neutralPluginManifestPaths,
      );
      warnings.addAll([
        for (final id in poolResult.skippedMissingIds) 'plugin_missing_$id',
        ...poolResult.errors,
      ]);
      await pluginProvisioner.provision(
        PluginProvisionContext(
          fs: fs,
          teampilotRoot: basePath,
          configDir: configDir,
          bundlePoolDir: layout.sessionRuntimePluginsDir(
            trimmedWorkspaceId,
            trimmedSessionId,
            cli.value,
            memberId: memberId,
          ),
          enabledPluginIds: enabledPlugins,
          installedCatalog: installedCatalog,
          layout: layout,
          tool: cli,
          memberProvisionJson: poolResult.memberProvisionStampJson,
          mcpConfigFileName: warmTier
              ? CursorWorkspaceWarmTier.mcpBaseFileName
              : null,
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
    return warnings;
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

    final total = Stopwatch()..start();
    Future<void> step(String name, Future<void> Function() run) async {
      final sw = Stopwatch()..start();
      await run();
      appLogger.d(
        '[session-launch] stage-fs $name '
        'session=$trimmedSessionId cli=${cli.value} '
        'ms=${sw.elapsedMilliseconds}',
      );
    }

    final warnings = <String>[];
    await step(
      'inherit-workspace',
      () => layout.ensureSessionRuntimeInheritsWorkspace(
        trimmedWorkspaceId,
        trimmedSessionId,
        cli.value,
      ),
    );

    final configDir = _launchResourceConfigDir(
      cli: cli,
      workspaceId: trimmedWorkspaceId,
      sessionId: trimmedSessionId,
    );
    // Share the persisted marketplace clone into this session's CONFIG_DIR so
    // the CLI reuses one per-tool flavor dir instead of cloning per session.
    await step(
      'marketplaces',
      () => MarketplaceSharedStore(fs: fs, teampilotRoot: basePath)
          .ensureSessionMarketplacesLinked(configDir: configDir, tool: cli),
    );

    // Catalog skills land in `skill/` BEFORE plugin bundles are decomposed:
    // the skills materializer reconciles `skill/` to exactly the catalog set,
    // so running it after plugin provision would prune plugin-provided skills.
    // Plugin decompose then fills only the names the catalog does not provide.
    await step('skills', () async {
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
    });

    final pluginProvisioner = _cliRegistry
        .capability<PluginCapability>(cli);
    if (pluginProvisioner != null) {
      late final List<Plugin> installedCatalog;
      late final PluginBundlePoolResult poolResult;
      await step('plugin-catalog', () async {
        installedCatalog = await InstalledPluginCatalog.load(fs, basePath);
      });
      await step('plugin-pool', () async {
        poolResult = await PluginBundlePoolService(
          fs: fs,
          teampilotRoot: basePath,
        ).reconcile(
          poolDir: layout.sessionRuntimePluginsDir(
            trimmedWorkspaceId,
            trimmedSessionId,
            cli.value,
          ),
          enabledPluginIds: runtimeBundle.pluginIds,
          installedCatalog: installedCatalog,
          paths: pluginProvisioner.manifestPaths ?? neutralPluginManifestPaths,
        );
      });
      warnings.addAll([
        for (final id in poolResult.skippedMissingIds) 'plugin_missing_$id',
        ...poolResult.errors,
      ]);
      await step(
        'plugin-provision',
        () => pluginProvisioner.provision(
          PluginProvisionContext(
            fs: fs,
            teampilotRoot: basePath,
            configDir: configDir,
            bundlePoolDir: layout.sessionRuntimePluginsDir(
              trimmedWorkspaceId,
              trimmedSessionId,
              cli.value,
            ),
            enabledPluginIds: runtimeBundle.pluginIds,
            installedCatalog: installedCatalog,
            layout: layout,
            tool: cli,
            memberProvisionJson: poolResult.memberProvisionStampJson,
          ),
        ),
      );
    }

    await step(
      'mcp',
      () => McpRegistryService(
        fs: fs,
        layout: layout,
      ).writeForSimpleSession(
        workspaceId: trimmedWorkspaceId,
        sessionId: trimmedSessionId,
        mcpServerIds: runtimeBundle.mcpServerIds,
        extraServers: extraMcpServers,
        projectMcpRoots: projectMcpRoots,
      ),
    );

    appLogger.d(
      '[session-launch] stage-fs done '
      'session=$trimmedSessionId cli=${cli.value} '
      'plugins=${runtimeBundle.pluginIds.length} '
      'skills=${runtimeBundle.skillIds.length} '
      'ms=${total.elapsedMilliseconds}',
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
    MemberAgentStatusEndpoint? agentStatus,
    List<HookEntry> hooks = const [],
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

    final cap = _cliRegistry.capability<ProviderCapability>(cli);
    if (cap == null) {
      return TeamLaunchOutcome(
        environment: const {},
        warnings: [...warnings, 'unknown_cli_${cli.value}'],
      );
    }

    SessionHomeContribution contribution;
    try {
      contribution = await cap.materializeSessionHome(
        sessionHomeContextFromLaunch(
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
            agentStatus: agentStatus,
            hooks: hooks,
          ),
          cli,
        ),
      );
    } on Object catch (e, st) {
      // Let the exception propagate — silently returning an empty environment
      // produces a broken session.  The caller surfaces the error as a proper
      // session-connect failure.
      Error.throwWithStackTrace(e, st);
    }

    return TeamLaunchOutcome(
      environment: _withAgentStatusEnv(contribution.environment, agentStatus),
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
    MemberAgentStatusEndpoint? agentStatus,
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
    final fsSw = Stopwatch()..start();
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
    appLogger.d(
      '[session-launch] stage-simple apply-fs '
      'session=$sessionId ms=${fsSw.elapsedMilliseconds} '
      'ops=${manifest.entries.length}',
    );
    final contributeSw = Stopwatch()..start();
    final hooksResult = await HookLibraryResolver(
      fs: readDelegate,
      teampilotRoot: workTeampilotRoot,
    ).resolve(runtimeBundle.hookIds);
    final outcome = await staging.contributeSimpleSessionLaunch(
      workspaceId: workspaceId,
      sessionId: sessionId,
      member: member,
      workingDirectory: workingDirectory,
      additionalDirectories: additionalDirectories,
      busIdle: busIdle,
      agentStatus: agentStatus,
      hooks: hooksResult.entries,
    );
    appLogger.d(
      '[session-launch] stage-simple contribute '
      'session=$sessionId ms=${contributeSw.elapsedMilliseconds} '
      'ops=${manifest.entries.length}',
    );
    return (
      outcome: TeamLaunchOutcome(
        environment: outcome.environment,
        warnings: [
          ...fsWarnings,
          ...hooksResult.warnings,
          ...outcome.warnings,
        ],
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
    MemberAgentStatusEndpoint? agentStatus,
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
      agentStatus: agentStatus,
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
    MemberAgentStatusEndpoint? agentStatus,
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

    // Catalog skills land in `skill/` BEFORE the session profile is staged:
    // `ensureSessionProfile` decomposes plugin skills into the same dir, and
    // the skills materializer would prune them if it ran afterwards. It
    // reconciles `skill/` to exactly the catalog set, then the plugin
    // decompose fills only the names the catalog does not provide.
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

    warnings.addAll(
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
      ),
    );

    final cap = _cliRegistry.capability<ProviderCapability>(launchCli);
    if (cap == null) {
      return (
        outcome: TeamLaunchOutcome(
          environment: const {},
          warnings: [...warnings, 'unknown_cli_${launchCli.value}'],
        ),
        manifest: manifest,
      );
    }

    final hooksResult = await HookLibraryResolver(
      fs: readDelegate,
      teampilotRoot: workTeampilotRoot,
    ).resolve(runtimeBundle.hookIds);
    warnings.addAll(hooksResult.warnings);

    SessionHomeContribution contribution;
    try {
      contribution = await cap.materializeSessionHome(
        sessionHomeContextFromLaunch(
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
            agentStatus: agentStatus,
            memberId: memberId,
            hooks: hooksResult.entries,
          ),
          launchCli,
        ),
      );
    } on Object catch (e, st) {
      // Let the exception propagate — silently returning an empty environment
      // produces a broken session that starts without CLI config, settings, or
      // role prompt (members launch with Environment: null).  The caller
      // (SessionConnectOrchestrator / SessionShellConnector) surfaces the error
      // as a proper session-connect failure.
      Error.throwWithStackTrace(e, st);
    }

    return (
      outcome: TeamLaunchOutcome(
        environment: _withAgentStatusEnv(contribution.environment, agentStatus),
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
    MemberAgentStatusEndpoint? agentStatus,
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
      agentStatus: agentStatus,
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
  Future<List<ExtensionSettingsHook>> extensionSettingsHooks(
    String? memberToolDir, {
    required String tool,
    String? teamId,
    String? workspaceId,
  }) => _infra.extensionSettingsHooks(
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
  Future<String?> resolveTeamLeadDelegateHookCommand(
    TeamMemberConfig member,
    String memberToolDir, {
    required bool forceTeamLeadDelegateMode,
  }) => _infra.resolveTeamLeadDelegateHookCommand(
    member,
    memberToolDir,
    forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
  );

  @override
  HostExecutionEnvironment hostEnvironmentForProvision() =>
      _infra.hostEnvironmentForProvision();
}

Map<String, String> _withAgentStatusEnv(
  Map<String, String> environment,
  MemberAgentStatusEndpoint? agentStatus,
) {
  if (agentStatus == null) return environment;
  return {...environment, agentStatusUrlEnvKey: agentStatus.url};
}
