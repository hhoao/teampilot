import 'dart:async';

import 'package:path/path.dart' as p;

import '../../models/config_bundle.dart';
import '../../models/cli_preset.dart';
import '../../models/extension_manifest.dart';
import '../../models/plugin.dart';
import '../../models/skill.dart';
import '../../models/team_config.dart';
import '../../utils/logging/logger.dart';
import '../../utils/team/team_member_naming.dart';
import '../team_bus/member_bus_idle_endpoint.dart';
import '../agent_status/member_agent_status_endpoint.dart';
import '../storage/runtime_layout.dart';
import '../extension/extension_detector.dart';
import '../extension/extension_provisioner.dart';
import '../host/host_execution_environment.dart';
import '../host/host_one_shot_runner.dart';
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
import '../resource/resource_scope.dart';
import '../resource/cli_resource_provisioner.dart';
import '../resource/resource_provider_set.dart';
import '../catalog/providers/catalog_prompt_provider.dart';
import '../catalog/providers/managed_catalog_skill_provider.dart';
import '../resource/providers/catalog_skill_contribution_provider.dart';
import '../resource/providers/plugin_skill_contribution_provider.dart';
import '../resource/providers/endpoint_hook_contribution_provider.dart';
import '../resource/providers/bus_awareness_hook_contribution_provider.dart';
import '../resource/providers/extension_hook_contribution_provider.dart';
import '../resource/providers/managed_hook_contribution_provider.dart';
import '../resource/providers/hook_contribution_provider.dart';
import '../resource/contribution/resource_assembly_error.dart';
import '../launch/launch_manifest.dart';
import '../launch/launch_manifest_paths.dart';
import '../launch/manifest_executor.dart';
import '../launch/manifest_filesystem.dart';
import '../provider/workspace_trust_provisioner.dart';
import '../cli/claude/team_roster_service.dart';
import '../cli/cursor/provider/cursor_workspace_warm_tier.dart';
import '../cli/cursor/provider/cursor_home_layout.dart';
import '../cli/registry/capabilities/cli_session_capability.dart';
import '../storage/app_storage.dart';
import '../cli/preset_resolver.dart';
import '../hook/hook_library_resolver.dart';
import '../resource/providers/hook_library_contribution_provider.dart';
import '../cli/registry/config_profile/config_profile_context.dart';
import '../cli/registry/config_profile/hook_seat_context_completer.dart';
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
  static final _nativePluginLocks = <String, Future<void>>{};

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
    HostOneShotRunner? hostOneShotRunner,
    String? cliExecutable,
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
       _hostOneShotRunner = hostOneShotRunner,
       _cliExecutable = cliExecutable,
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
    HostOneShotRunner? hostOneShotRunner,
    String? cliExecutable,
  }) : _infra = infra,
       _catalogOverride = catalog,
       _hostOneShotRunner = hostOneShotRunner,
       _cliExecutable = cliExecutable,
       _cliRegistry = cliRegistry ?? _defaultCliRegistry,
       _loadInstalledSkills = loadInstalledSkills,
       _loadGlobalPresets = loadGlobalPresets,
       _projectConfigRepository = projectConfigRepository;

  final ConfigProfileInfrastructure _infra;
  final ConfigProfilePaths? _catalogOverride;
  final HostOneShotRunner? _hostOneShotRunner;
  final String? _cliExecutable;
  final CliToolRegistry _cliRegistry;
  final Future<List<Skill>> Function()? _loadInstalledSkills;
  final Future<List<CliPreset>> Function() _loadGlobalPresets;
  final WorkspaceProjectConfigRepository? _projectConfigRepository;

  List<String> get _nativeCliPathPrepend {
    final path = _infra.pathContext;
    final prefixes = <String>[
      path.join(_infra.basePath, 'toolchain', 'node', 'current', 'bin'),
    ];
    final home = _infra.home.trim();
    if (home.isNotEmpty) {
      prefixes.add(path.join(home, '.local', 'bin'));
    }
    return prefixes;
  }

  /// Control-plane paths for provider catalog reads (home when work != home).
  ConfigProfilePaths get catalog => _catalogOverride ?? _infra;

  Future<ResourceCatalog> _skillCatalog() async {
    final skills =
        await (_loadInstalledSkills?.call() ?? Future.value(const <Skill>[]));
    return ResourceCatalog(
      skills: skills,
      skillsRoot: AppPaths.skillsDirForTeampilotRoot(catalog.basePath),
      pathContext: fs.pathContext,
      plugins: await InstalledPluginCatalog.load(fs, catalog.basePath),
      pluginsRoot: AppPaths.pluginsDirForTeampilotRoot(catalog.basePath),
    );
  }

  Future<ResourceProvisionReport> _provisionStagedResources({
    required CliResourceProvisionContext context,
  }) async {
    final report = await CliResourceProvisioner(
      fs: context.fs,
      registry: _cliRegistry,
    ).provision(context);
    if (report.hardDiagnostics.isNotEmpty) {
      throw ResourceAssemblyException(report.hardDiagnostics);
    }
    appLogger.d(
      '[resource-debug] prompt=${report.prompt?.content.length} '
      'promptMaterialized=${report.promptMaterialization?.written} '
      'env=${report.promptMaterialization?.environment} '
      'hooks=${report.hooks.length} '
      'hookMaterialized=${report.materializations[ResourceContributionKind.hook]?.materialized} '
      'hard=${report.hardDiagnostics.length}',
    );
    return report;
  }

  Future<ResourceProvisionReport> _provisionStagedHooks({
    required CliResourceProvisionContext context,
  }) async {
    final report = await CliResourceProvisioner(
      fs: context.fs,
      registry: _cliRegistry,
    ).provisionHooks(context);
    if (report.hardDiagnostics.isNotEmpty) {
      throw ResourceAssemblyException(report.hardDiagnostics);
    }
    return report;
  }

  Future<void> _provisionStagedRosterHooks({
    required ConfigProfileService staging,
    required Filesystem stagingFs,
    required String workspaceId,
    required String sessionId,
    required String teamId,
    required String cliTeamName,
    required TeamProfile? team,
    required CliTool defaultCli,
    required List<TeamMemberConfig> members,
    required String? materializedMemberId,
    required ConfigBundle runtimeBundle,
    required String workingDirectory,
    required List<String> additionalDirectories,
    required MemberBusIdleEndpoint? busIdle,
    required MemberAgentStatusEndpoint? agentStatus,
    required List<String> hookIds,
    required List<String> warnings,
  }) async {
    for (final member in members.where((member) => member.isValid)) {
      if (member.id == materializedMemberId) continue;
      final mixed = team?.teamMode == TeamMode.mixed;
      final memberId = mixed
          ? ClaudeTeamRosterService.safeClaudePathSegment(member.id)
          : null;
      final memberCli = team == null
          ? defaultCli
          : mixed
          ? member.cli ?? team.cli
          : team.cli;
      final scope = resolveLaunchProfileScope(
        workspaceId: workspaceId,
        teamId: teamId,
        appSessionId: sessionId,
        cliTeamName: cliTeamName,
        memberId: memberId,
      );
      final memberToolDir = staging.sessionToolDir(
        workspaceId,
        sessionId,
        memberCli.value,
        memberId: memberId,
      );
      final hookProviders = await staging._launchHookProviders(
        delegate: staging,
        cli: memberCli,
        scope: scope,
        team: team,
        member: member,
        busIdle: busIdle,
        agentStatus: agentStatus,
        memberToolDir: memberToolDir,
        hookIds: hookIds,
        simple: false,
      );
      final hookPaths = staging._hookMaterializationPaths(
        cli: memberCli,
        memberToolDir: memberToolDir,
        member: member,
        memberHome: memberCli == CliTool.cursor
            ? stagingFs.pathContext.join(memberToolDir, 'home')
            : null,
      );
      final report = await staging._provisionStagedHooks(
        context: CliResourceProvisionContext(
          cli: memberCli,
          scope: team == null
              ? WorkspaceResourceScope(bundle: runtimeBundle)
              : TeamResourceScope(team: team, member: member),
          runtimeBundle: runtimeBundle,
          fs: stagingFs,
          layout: staging.layout,
          configDir: staging._launchResourceConfigDir(
            cli: memberCli,
            workspaceId: workspaceId,
            sessionId: sessionId,
            memberId: memberId,
            team: team,
          ),
          resourceProviders: ResourceProviderSet(hooks: hookProviders.hooks),
          paths: staging,
          launchScope: scope,
          member: member,
          members: [member],
          workingDirectory: workingDirectory,
          additionalDirectories: additionalDirectories,
          mixed: mixed,
          pushDelivery: mixed,
          hooksDir: hookPaths.hooksDir,
          hookConfigPath: hookPaths.configPath,
        ),
      );
      warnings.addAll(staging._resourceWarnings(report));
    }
  }

  List<String> _resourceWarnings(ResourceProvisionReport report) => [
    ...report.warnings.map((diagnostic) => diagnostic.message),
    for (final result in report.materializations.values) ...result.warnings,
  ];

  ResourceProviderSet _catalogResourceProviders(ResourceCatalog catalog) =>
      ResourceProviderSet(
        prompts: const [CatalogPromptProvider()],
        skills: [
          ManagedCatalogSkillProvider(),
          CatalogSkillContributionProvider(catalog: catalog),
          PluginSkillContributionProvider(
            catalog: catalog,
            pluginsRoot: catalog.pluginsRoot,
          ),
        ],
      );

  Future<ResourceProviderSet> _launchHookProviders({
    required ConfigProfileDelegate delegate,
    required CliTool cli,
    required LaunchProfileScope scope,
    required TeamProfile? team,
    required TeamMemberConfig? member,
    required MemberBusIdleEndpoint? busIdle,
    required MemberAgentStatusEndpoint? agentStatus,
    required String memberToolDir,
    required Iterable<String> hookIds,
    required bool simple,
    Iterable<HookContributionProvider> injected = const [],
  }) async {
    const completer = HookSeatContextCompleter();
    final managed = <HookContributionProvider>[];
    if (member != null && member.isValid) {
      if (team?.teamMode == TeamMode.mixed) {
        managed.add(const BusAwarenessHookContributionProvider());
      }
      if (busIdle != null && (simple || team?.teamMode == TeamMode.mixed)) {
        managed.add(
          BusIdleHookContributionProvider(
            endpoint: busIdle,
            memberId: member.id,
          ),
        );
      }
      if (agentStatus != null) {
        managed.add(
          AgentStatusHookContributionProvider(
            endpoint: agentStatus,
            memberId: member.id,
          ),
        );
      }
      final delegateCommand = await delegate.resolveTeamLeadDelegateHookCommand(
        member,
        memberToolDir,
        forceTeamLeadDelegateMode:
            team?.forceTeamLeadDelegateMode == true &&
            TeamMemberNaming.isTeamLead(member),
      );
      if (delegateCommand != null) {
        managed.add(
          ManagedHookContributionProvider(
            entries: completer.delegateHooks(commands: [delegateCommand]),
            providerId: 'team-lead-delegate',
          ),
        );
      }
      final selfCommand = await delegate.resolveTeamLeadSelfHookCommand(
        member,
        memberToolDir,
      );
      if (selfCommand != null) {
        managed.add(
          ManagedHookContributionProvider(
            entries: completer.teamLeadSelfHooks(
              member: member,
              command: selfCommand,
            ),
            providerId: 'team-lead-self',
          ),
        );
      }
    }

    final extensionHooks = await delegate.extensionSettingsHooks(
      memberToolDir,
      tool: cli.value,
      teamId: simple ? null : scope.teamId,
      workspaceId: simple ? scope.workspaceId : null,
    );
    final user = HookLibraryContributionProvider(
      resolver: HookLibraryResolver(
        fs: delegate.fs,
        teampilotRoot: delegate.basePath,
      ),
      hookIds: hookIds,
    );
    return ResourceProviderSet(
      hooks: [
        ...managed,
        if (extensionHooks.isNotEmpty)
          ExtensionHookContributionProvider(settingsHooks: extensionHooks),
        ...injected,
        user,
      ],
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

  /// Runs CLI-owned plugin installation serially for each target config dir.
  /// Native teams share one CODEX_HOME, so concurrent member connects must not
  /// replace the marketplace while another member is installing from it.
  Future<T> _withNativePluginLock<T>(
    String key,
    Future<T> Function() action,
  ) async {
    final previous = _nativePluginLocks[key] ?? Future<void>.value();
    final gate = Completer<void>();
    final queued = previous.then((_) => gate.future);
    _nativePluginLocks[key] = queued;
    try {
      await previous;
      return await action();
    } finally {
      if (!gate.isCompleted) gate.complete();
      if (identical(_nativePluginLocks[key], queued)) {
        _nativePluginLocks.remove(key);
      }
    }
  }

  /// Runs CLI-owned plugin installation after a launch manifest has been
  /// flushed to the target filesystem.
  Future<void> provisionNativePlugins({
    required String workspaceId,
    required String sessionId,
    required ConfigBundle runtimeBundle,
    required CliTool cli,
    String? memberId,
    TeamProfile? team,
    String? executable,
  }) async {
    final pluginProvisioner = _cliRegistry.capability<PluginCapability>(cli);
    if (pluginProvisioner == null ||
        pluginProvisioner.runtimeOwnership != PluginRuntimeOwnership.native) {
      return;
    }
    final bundlePoolDir = layout.sessionRuntimePluginPoolDir(
      workspaceId,
      sessionId,
      cli.value,
      memberId: memberId,
    );
    final configDir = _launchResourceConfigDir(
      cli: cli,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: memberId,
      team: team,
    );
    final lockKey = configDir;
    await _withNativePluginLock(lockKey, () async {
      final installedCatalog = await InstalledPluginCatalog.load(fs, basePath);
      final started = Stopwatch()..start();
      await pluginProvisioner.provision(
        PluginProvisionContext(
          fs: fs,
          teampilotRoot: basePath,
          configDir: configDir,
          bundlePoolDir: bundlePoolDir,
          enabledPluginIds: runtimeBundle.pluginIds,
          installedCatalog: installedCatalog,
          layout: layout,
          tool: cli,
          hostOneShotRunner: _hostOneShotRunner,
          executable: executable ?? _cliExecutable,
          pathPrepend: _nativeCliPathPrepend,
        ),
      );
      appLogger.d(
        '[session-launch] native-plugin-provision done '
        'session=$sessionId cli=${cli.value} '
        'ms=${started.elapsedMilliseconds}',
      );
    });
  }

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
  }) => _infra.sessionToolDir(workspaceId, sessionId, tool, memberId: memberId);

  String _launchResourceConfigDir({
    required CliTool cli,
    required String workspaceId,
    required String sessionId,
    String? memberId,
    TeamProfile? team,
  }) {
    if (CursorWorkspaceWarmTier.applies(team: team, cli: cli)) {
      return CursorWorkspaceWarmTier.sharedRoot(layout, workspaceId, team!.id);
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

  ({String hooksDir, String? configPath}) _hookMaterializationPaths({
    required CliTool cli,
    required String memberToolDir,
    required TeamMemberConfig? member,
    required String? memberHome,
  }) {
    if (cli == CliTool.cursor && memberHome != null) {
      final cursor = CursorHomeLayout(pathContext: pathContext);
      return (
        hooksDir: cursor.hooksDir(memberHome),
        configPath: cursor.hooksConfig(memberHome),
      );
    }
    if (cli == CliTool.claude && member != null && member.isValid) {
      return (
        hooksDir: pathContext.join(memberToolDir, 'hooks'),
        configPath: pathContext.join(
          memberToolDir,
          'settings',
          '${ClaudeTeamRosterService.safeClaudePathSegment(member.id)}.json',
        ),
      );
    }
    return (
      hooksDir: pathContext.join(memberToolDir, 'hooks'),
      configPath: null,
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
    List<String> additionalDirectories = const [],
    MemberBusIdleEndpoint? busIdle,
    bool provisionResources = true,
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
    await MarketplaceSharedStore(
      fs: fs,
      teampilotRoot: basePath,
    ).ensureSessionMarketplacesLinked(configDir: configDir, tool: cli);
    final pluginProvisioner = _cliRegistry.capability<PluginCapability>(cli);
    final warmTier = CursorWorkspaceWarmTier.applies(team: team, cli: cli);
    final mcpRegistry = McpRegistryService(fs: fs, layout: layout);
    McpRegistryAssembly? mcpAssembly;
    List<Plugin>? installedCatalog;
    if (pluginProvisioner != null) {
      installedCatalog = await InstalledPluginCatalog.load(fs, basePath);
      final enabledPlugins = runtimeBundle?.pluginIds ?? const <String>[];
      final pluginPoolDir =
          pluginProvisioner.runtimeOwnership == PluginRuntimeOwnership.native
          ? layout.sessionRuntimePluginPoolDir(
              trimmedWorkspaceId,
              trimmedSessionId,
              cli.value,
              memberId: memberId,
            )
          : layout.sessionRuntimePluginsDir(
              trimmedWorkspaceId,
              trimmedSessionId,
              cli.value,
              memberId: memberId,
            );
      final poolResult =
          await PluginBundlePoolService(
            fs: fs,
            teampilotRoot: basePath,
          ).reconcile(
            poolDir: pluginPoolDir,
            enabledPluginIds: enabledPlugins,
            installedCatalog: installedCatalog,
            paths:
                pluginProvisioner.manifestPaths ?? neutralPluginManifestPaths,
          );
      warnings.addAll([
        for (final id in poolResult.skippedMissingIds) 'plugin_missing_$id',
        ...poolResult.errors,
      ]);
      if (provisionResources) {
        mcpAssembly = await mcpRegistry.assembleForTeam(
          cli: cli,
          teamId: trimmedTeamId,
          extraServers: extraMcpServers,
          pluginIds: enabledPlugins,
          installedPluginCatalog: installedCatalog,
        );
        await pluginProvisioner.provision(
          PluginProvisionContext(
            fs: fs,
            teampilotRoot: basePath,
            configDir: configDir,
            bundlePoolDir: pluginPoolDir,
            enabledPluginIds: enabledPlugins,
            installedCatalog: installedCatalog,
            layout: layout,
            tool: cli,
            memberProvisionJson: poolResult.memberProvisionStampJson,
            assembledMcpServers: mcpAssembly?.result.servers ?? const [],
            mcpConfigFileName: warmTier
                ? CursorWorkspaceWarmTier.mcpBaseFileName
                : null,
          ),
        );
      }
    }
    await _cliRegistry
        .lifecycleFor(cli)
        .ensurePersisted(
          CliSessionPersistContext(
            workspaceId: trimmedWorkspaceId,
            sessionId: trimmedSessionId,
            memberId: memberId,
            tool: cli,
            paths: this,
            team: team,
            busIdle: busIdle,
            workingDirectory: workingDirectory,
            additionalDirectories: additionalDirectories,
          ),
        );
    if (!provisionResources) return warnings;
    mcpAssembly ??= await mcpRegistry.assembleForTeam(
      cli: cli,
      teamId: trimmedTeamId,
      extraServers: extraMcpServers,
      pluginIds: runtimeBundle?.pluginIds ?? const [],
      installedPluginCatalog: installedCatalog,
    );
    final assembledMcp = mcpAssembly;
    if (warmTier) {
      await mcpRegistry.writeCursorWorkspaceMcpBase(
        workspaceId: trimmedWorkspaceId,
        teamId: trimmedTeamId,
        extraServers: extraMcpServers,
        pluginIds: runtimeBundle?.pluginIds ?? const [],
        projectMcpRoots: projectMcpRoots,
        assembly: assembledMcp,
        mcpAlreadyMaterialized: pluginProvisioner?.writesAssembledMcp == true,
      );
      final trimmedMemberId = memberId?.trim() ?? '';
      if (trimmedMemberId.isNotEmpty) {
        await mcpRegistry.mergeCursorMemberMcpCredentials(
          workspaceId: trimmedWorkspaceId,
          sessionId: trimmedSessionId,
          teamId: trimmedTeamId,
          memberId: trimmedMemberId,
          assembly: assembledMcp,
        );
      }
    } else {
      await mcpRegistry.writeForSession(
        workspaceId: trimmedWorkspaceId,
        teamId: trimmedTeamId,
        sessionId: trimmedSessionId,
        cli: cli,
        memberId: memberId,
        extraServers: extraMcpServers,
        pluginIds: runtimeBundle?.pluginIds ?? const [],
        projectMcpRoots: projectMcpRoots,
        assembly: assembledMcp,
        mcpAlreadyMaterialized: pluginProvisioner?.writesAssembledMcp == true,
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
    ConfigProfileDelegate? promptPaths,
    LaunchProfileScope? launchScope,
    TeamMemberConfig? member,
    Iterable<TeamMemberConfig> members = const [],
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
    String? memberHome,
    Map<String, String>? resourceEnvironment,
    String workingDirectory = '',
    Iterable<String> additionalDirectories = const [],
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
      () => MarketplaceSharedStore(
        fs: fs,
        teampilotRoot: basePath,
      ).ensureSessionMarketplacesLinked(configDir: configDir, tool: cli),
    );

    final pluginProvisioner = _cliRegistry.capability<PluginCapability>(cli);
    final mcpRegistry = McpRegistryService(fs: fs, layout: layout);
    List<Plugin>? installedCatalog;
    String? pluginPoolDir;
    PluginBundlePoolResult? poolResult;
    if (pluginProvisioner != null) {
      pluginPoolDir =
          pluginProvisioner.runtimeOwnership == PluginRuntimeOwnership.native
          ? layout.sessionRuntimePluginPoolDir(
              trimmedWorkspaceId,
              trimmedSessionId,
              cli.value,
            )
          : layout.sessionRuntimePluginsDir(
              trimmedWorkspaceId,
              trimmedSessionId,
              cli.value,
            );
      await step('plugin-catalog', () async {
        installedCatalog = await InstalledPluginCatalog.load(fs, basePath);
      });
      final pluginCatalog = installedCatalog!;
      await step('plugin-pool', () async {
        poolResult =
            await PluginBundlePoolService(
              fs: fs,
              teampilotRoot: basePath,
            ).reconcile(
              poolDir: pluginPoolDir!,
              enabledPluginIds: runtimeBundle.pluginIds,
              installedCatalog: pluginCatalog,
              paths:
                  pluginProvisioner.manifestPaths ?? neutralPluginManifestPaths,
            );
      });
      warnings.addAll([
        for (final id in poolResult!.skippedMissingIds) 'plugin_missing_$id',
        ...poolResult!.errors,
      ]);
    }

    final mcpProviders = await mcpRegistry.providersForSimple(
      cli: cli,
      mcpServerIds: runtimeBundle.mcpServerIds,
      extraServers: extraMcpServers,
      pluginIds: runtimeBundle.pluginIds,
      installedPluginCatalog: installedCatalog,
    );
    final resourceCatalog = await _skillCatalog();
    await step('resources', () async {
      await maybeRemoveStaleProjectTeammateBus(
        fs: fs,
        extraServers: extraMcpServers,
        projectRoots: projectMcpRoots,
      );
      final providers = _catalogResourceProviders(resourceCatalog);
      final hookProviders = await _launchHookProviders(
        delegate: this,
        cli: cli,
        scope:
            launchScope ??
            LaunchProfileScope(
              workspaceId: trimmedWorkspaceId,
              teamId: trimmedWorkspaceId,
              sessionId: trimmedSessionId,
              cliTeamName: trimmedSessionId,
            ),
        team: null,
        member: member,
        busIdle: busIdle,
        agentStatus: agentStatus,
        memberToolDir: sessionToolDir(
          trimmedWorkspaceId,
          trimmedSessionId,
          cli.value,
        ),
        hookIds: runtimeBundle.hookIds,
        simple: true,
      );
      final hookPaths = _hookMaterializationPaths(
        cli: cli,
        memberToolDir: sessionToolDir(
          trimmedWorkspaceId,
          trimmedSessionId,
          cli.value,
        ),
        member: member,
        memberHome: memberHome,
      );
      final report = await _provisionStagedResources(
        context: CliResourceProvisionContext(
          cli: cli,
          scope: SimpleResourceScope(bundle: runtimeBundle),
          runtimeBundle: runtimeBundle,
          fs: fs,
          layout: layout,
          configDir: configDir,
          resourceProviders: ResourceProviderSet(
            prompts: providers.prompts,
            skills: providers.skills,
            mcp: mcpProviders.providers.mcp,
            hooks: hookProviders.hooks,
          ),
          paths: promptPaths,
          launchScope: launchScope,
          member: member,
          members: members,
          workingDirectory: workingDirectory,
          additionalDirectories: additionalDirectories,
          memberHome: memberHome,
          hooksDir: hookPaths.hooksDir,
          hookConfigPath: hookPaths.configPath,
          appConfigDir: mcpProviders.catalogProvider != null
              ? layout.appToolRoot(cli.value)
              : null,
        ),
      );
      warnings.addAll(_resourceWarnings(report));
      resourceEnvironment?.addAll(
        report.promptMaterialization?.environment ?? const {},
      );
    });

    // Skill reconcile (always-on teampilot-catalog) must run before plugin
    // decompose. Otherwise reconcile prunes plugin-only skills that are not
    // listed in plugins.json metadata.
    if (pluginProvisioner != null &&
        pluginPoolDir != null &&
        poolResult != null &&
        installedCatalog != null) {
      await step(
        'plugin-provision',
        () => pluginProvisioner.provision(
          PluginProvisionContext(
            fs: fs,
            teampilotRoot: basePath,
            configDir: configDir,
            bundlePoolDir: pluginPoolDir!,
            enabledPluginIds: runtimeBundle.pluginIds,
            installedCatalog: installedCatalog!,
            layout: layout,
            tool: cli,
            memberProvisionJson: poolResult!.memberProvisionStampJson,
            assembledMcpServers: const [],
          ),
        ),
      );
    }

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
    ResourceProviderSet resourceProviders = ResourceProviderSet.empty,
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
            resourceProviders: resourceProviders,
            promptAlreadyMaterialized: true,
            hooksAlreadyMaterialized: true,
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
    final simpleScope = LaunchProfileScope(
      workspaceId: workspaceId.trim(),
      teamId: workspaceId.trim(),
      sessionId: sessionId.trim(),
      cliTeamName: sessionId.trim(),
    );
    final simpleMemberHome = member.cli == CliTool.cursor
        ? stagingFs.pathContext.join(
            staging.sessionToolDir(workspaceId, sessionId, cli.value),
            'home',
          )
        : null;
    final resourceEnvironment = <String, String>{};
    final fsSw = Stopwatch()..start();
    final fsWarnings = await staging.applySimpleSessionFilesystem(
      workspaceId: workspaceId,
      sessionId: sessionId,
      runtimeBundle: runtimeBundle,
      cli: cli,
      extraMcpServers: extraMcpServers,
      promptPaths: staging,
      launchScope: simpleScope,
      member: member,
      members: [member],
      busIdle: busIdle,
      agentStatus: agentStatus,
      memberHome: simpleMemberHome,
      resourceEnvironment: resourceEnvironment,
      workingDirectory: workingDirectory,
      additionalDirectories: additionalDirectories,
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
    final outcome = await staging.contributeSimpleSessionLaunch(
      workspaceId: workspaceId,
      sessionId: sessionId,
      member: member,
      workingDirectory: workingDirectory,
      additionalDirectories: additionalDirectories,
      busIdle: busIdle,
      agentStatus: agentStatus,
      resourceProviders: ResourceProviderSet.empty,
    );
    appLogger.d(
      '[session-launch] stage-simple contribute '
      'session=$sessionId ms=${contributeSw.elapsedMilliseconds} '
      'ops=${manifest.entries.length}',
    );
    return (
      outcome: TeamLaunchOutcome(
        environment: {...resourceEnvironment, ...outcome.environment},
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
    await provisionNativePlugins(
      workspaceId: workspaceId,
      sessionId: sessionId,
      runtimeBundle: runtimeBundle,
      cli: member.cli ?? CliTool.claude,
    );
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
        additionalDirectories: additionalDirectories,
        busIdle: busIdle,
        provisionResources: false,
      ),
    );

    final resourceCatalog = await _skillCatalog();
    final providers = _catalogResourceProviders(resourceCatalog);
    final mcpRegistry = McpRegistryService(
      fs: stagingFs,
      layout: staging.layout,
    );
    final mcpProviders = await mcpRegistry.providersForTeam(
      cli: launchCli,
      teamId: trimmedTeamId,
      extraServers: extraMcpServers,
      pluginIds: runtimeBundle.pluginIds,
    );
    await maybeRemoveStaleProjectTeammateBus(
      fs: stagingFs,
      extraServers: extraMcpServers,
      projectRoots: projectMcpRootsFromLaunch(
        workingDirectory: workingDirectory,
        additionalDirectories: additionalDirectories,
      ),
    );
    final resourceConfigDir = staging._launchResourceConfigDir(
      cli: launchCli,
      workspaceId: trimmedWorkspaceId,
      sessionId: trimmedSessionId,
      memberId: memberId,
      team: team,
    );
    final warmTier = CursorWorkspaceWarmTier.applies(
      team: team,
      cli: launchCli,
    );
    final hookMemberToolDir = staging.sessionToolDir(
      trimmedWorkspaceId,
      trimmedSessionId,
      launchCli.value,
      memberId: team?.teamMode == TeamMode.mixed ? memberId : null,
    );
    final hookProviders = await staging._launchHookProviders(
      delegate: staging,
      cli: launchCli,
      scope: scope,
      team: team,
      member: launchMember,
      busIdle: busIdle,
      agentStatus: agentStatus,
      memberToolDir: hookMemberToolDir,
      hookIds: runtimeBundle.hookIds,
      simple: team == null,
    );
    final hookPaths = staging._hookMaterializationPaths(
      cli: launchCli,
      memberToolDir: hookMemberToolDir,
      member: launchMember,
      memberHome: launchCli == CliTool.cursor && launchMember != null
          ? stagingFs.pathContext.join(hookMemberToolDir, 'home')
          : null,
    );
    final resourceReport = await _provisionStagedResources(
      context: CliResourceProvisionContext(
        cli: launchCli,
        scope: team == null
            ? WorkspaceResourceScope(bundle: runtimeBundle)
            : TeamResourceScope(team: team, member: launchMember),
        runtimeBundle: runtimeBundle,
        fs: stagingFs,
        layout: staging.layout,
        configDir: resourceConfigDir,
        resourceProviders: ResourceProviderSet(
          prompts: providers.prompts,
          skills: providers.skills,
          mcp: mcpProviders.providers.mcp,
          hooks: hookProviders.hooks,
        ),
        paths: staging,
        launchScope: scope,
        member: launchMember,
        members: launchMembers,
        forceTeamLeadDelegateMode: team?.forceTeamLeadDelegateMode ?? false,
        mixed: team?.teamMode == TeamMode.mixed,
        pushDelivery: team?.teamMode == TeamMode.mixed,
        workingDirectory: workingDirectory,
        additionalDirectories: additionalDirectories,
        memberHome: launchCli == CliTool.cursor && launchMember != null
            ? stagingFs.pathContext.join(hookMemberToolDir, 'home')
            : null,
        hooksDir: hookPaths.hooksDir,
        hookConfigPath: hookPaths.configPath,
        appConfigDir: mcpProviders.catalogProvider != null
            ? staging.layout.appToolRoot(launchCli.value)
            : null,
        mcpOutputBasename: warmTier
            ? CursorWorkspaceWarmTier.mcpBaseFileName
            : null,
      ),
    );
    warnings.addAll(_resourceWarnings(resourceReport));
    final pluginProvisioner = _cliRegistry.capability<PluginCapability>(
      launchCli,
    );
    if (pluginProvisioner != null) {
      final pluginCatalog = await InstalledPluginCatalog.load(
        stagingFs,
        staging.basePath,
      );
      final pluginPoolDir =
          pluginProvisioner.runtimeOwnership == PluginRuntimeOwnership.native
          ? staging.layout.sessionRuntimePluginPoolDir(
              trimmedWorkspaceId,
              trimmedSessionId,
              launchCli.value,
              memberId: memberId,
            )
          : staging.layout.sessionRuntimePluginsDir(
              trimmedWorkspaceId,
              trimmedSessionId,
              launchCli.value,
              memberId: memberId,
            );
      await pluginProvisioner.provision(
        PluginProvisionContext(
          fs: stagingFs,
          teampilotRoot: staging.basePath,
          configDir: resourceConfigDir,
          bundlePoolDir: pluginPoolDir,
          enabledPluginIds: runtimeBundle.pluginIds,
          installedCatalog: pluginCatalog,
          layout: staging.layout,
          tool: launchCli,
          assembledMcpServers: const [],
          mcpConfigFileName: warmTier
              ? CursorWorkspaceWarmTier.mcpBaseFileName
              : null,
        ),
      );
    }
    if (launchMembers.isNotEmpty) {
      await staging._provisionStagedRosterHooks(
        staging: staging,
        stagingFs: stagingFs,
        workspaceId: trimmedWorkspaceId,
        sessionId: trimmedSessionId,
        teamId: trimmedTeamId,
        cliTeamName: cliTeamName,
        team: team,
        defaultCli: launchCli,
        members: launchMembers,
        materializedMemberId: launchMember?.isValid == true
            ? launchMember!.id
            : null,
        runtimeBundle: runtimeBundle,
        workingDirectory: workingDirectory,
        additionalDirectories: additionalDirectories,
        busIdle: busIdle,
        agentStatus: agentStatus,
        hookIds: runtimeBundle.hookIds,
        warnings: warnings,
      );
    }

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
            resourceProviders: ResourceProviderSet.empty,
            promptAlreadyMaterialized: true,
            hooksAlreadyMaterialized: true,
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
        environment: {
          ...?resourceReport.promptMaterialization?.environment,
          ..._withAgentStatusEnv(contribution.environment, agentStatus),
        },
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
    await provisionNativePlugins(
      workspaceId: workspaceId,
      sessionId: sessionId,
      runtimeBundle: runtimeBundle,
      cli: cli,
      memberId: team?.teamMode == TeamMode.mixed && member != null
          ? ClaudeTeamRosterService.safeClaudePathSegment(member.id)
          : null,
      team: team,
    );
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
  Future<String?> resolveTeamLeadSelfHookCommand(
    TeamMemberConfig member,
    String memberToolDir,
  ) => _infra.resolveTeamLeadSelfHookCommand(member, memberToolDir);

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
