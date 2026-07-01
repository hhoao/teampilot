import 'package:path/path.dart' as p;

import '../../models/cli_preset.dart';
import '../../models/extension_manifest.dart';
import '../../models/personal_profile.dart';
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
import '../mcp/profile_mcp_linker_service.dart';
import '../../repositories/mcp_repository.dart';
import '../io/filesystem.dart';
import '../mcp/mcp_registry_service.dart';
import '../resource/resource_provisioning_service.dart';
import '../resource/resource_scope.dart';
import '../launch/launch_manifest.dart';
import '../launch/manifest_executor.dart';
import '../launch/manifest_filesystem.dart';
import '../provider/workspace_trust_provisioner.dart';
import '../team/claude_team_roster_service.dart';
import '../cli/registry/capabilities/cli_config_layout_capability.dart';
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
       _loadGlobalPresets = loadGlobalPresets;

  ConfigProfileService._fromInfrastructure({
    required ConfigProfileInfrastructure infra,
    ConfigProfilePaths? catalog,
    CliToolRegistry? cliRegistry,
    Future<List<Skill>> Function()? loadInstalledSkills,
    Future<List<CliPreset>> Function() loadGlobalPresets =
        _defaultLoadGlobalPresets,
  }) : _infra = infra,
       _catalogOverride = catalog,
       _cliRegistry = cliRegistry ?? _defaultCliRegistry,
       _loadInstalledSkills = loadInstalledSkills,
       _loadGlobalPresets = loadGlobalPresets;

  final ConfigProfileInfrastructure _infra;
  final ConfigProfilePaths? _catalogOverride;
  final CliToolRegistry _cliRegistry;
  final Future<List<Skill>> Function()? _loadInstalledSkills;
  final Future<List<CliPreset>> Function() _loadGlobalPresets;
  StandaloneLaunchProfileScope? _activeStandaloneScope;

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
    );
  }

  Future<
    ({
      TeamMemberConfig? member,
      List<TeamMemberConfig> members,
      CliTool cli,
    })
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
    final resolvedMember =
        member != null && member.isValid
            ? memberForLaunch(
                team: team,
                member: member,
                globalPresets: presets,
              )
            : member;
    final resolvedRoster = resolveTeamRosterForLaunch(
      team: team,
      members: roster,
      globalPresets: presets,
    );
    final effectiveCli =
        resolvedMember != null && resolvedMember.isValid
            ? (team.teamMode == TeamMode.mixed
                  ? resolvedMember.cli ?? team.cli
                  : team.cli)
            : cli;
    return (
      member: resolvedMember,
      members: resolvedRoster,
      cli: effectiveCli,
    );
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

  String standaloneSessionToolDir(
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
  }) {
    final scope = _activeStandaloneScope;
    if (scope != null) {
      return layout.sessionRuntimeToolDir(
        scope.workspaceId,
        scope.sessionId,
        tool,
        memberId: memberId,
      );
    }
    return _infra.sessionToolDir(
      workspaceId,
      sessionId,
      tool,
      memberId: memberId,
    );
  }

  String _launchResourceConfigDir({
    required CliTool cli,
    required String workspaceId,
    required String sessionId,
    String? memberId,
  }) =>
      sessionConfigDirForTool(
        cli,
        layout,
        workspaceId: workspaceId,
        sessionId: sessionId,
        memberId: memberId,
      );

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
    String? memberId,
    Map<String, Map<String, Object?>>? extraMcpServers,
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
    final pluginProvisioner = _cliRegistry.capability<PluginProvisionerCapability>(
      cli,
    );
    if (pluginProvisioner != null) {
      await pluginProvisioner.provision(
        PluginProvisionContext(
          fs: fs,
          teampilotRoot: basePath,
          configDir: _launchResourceConfigDir(
            cli: cli,
            workspaceId: trimmedWorkspaceId,
            sessionId: trimmedSessionId,
            memberId: memberId,
          ),
          bundlePoolDir: layout.sessionRuntimePluginsDir(
            trimmedWorkspaceId,
            trimmedSessionId,
            cli.value,
            memberId: memberId,
          ),
          enabledPluginIds: team?.pluginIds ?? const <String>[],
          installedCatalog: await InstalledPluginCatalog.load(fs, basePath),
          layout: layout,
          tool: cli,
          memberProvisionJson: memberProvisionJson,
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
    await McpRegistryService(fs: fs, layout: layout).writeForSession(
      workspaceId: trimmedWorkspaceId,
      teamId: trimmedTeamId,
      sessionId: trimmedSessionId,
      memberId: memberId,
      extraServers: extraMcpServers,
    );
  }

  Future<void> ensureStandalonePersonalProfile(
    String workspaceId, {
    CliTool cli = CliTool.claude,
  }) async {
    final trimmed = workspaceId.trim();
    if (trimmed.isEmpty) return;
    await layout.ensureWorkspaceConfigInheritsApp(trimmed, cli.value);
  }

  /// Phase A: workspace-level profile on the work machine (not per-session).
  Future<void> provisionWorkspace({
    required String workspaceId,
    required CliTool cli,
    required PersonalProfile personal,
    Iterable<String> trustedDirectories = const [],
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    if (trimmedWorkspaceId.isEmpty) return;

    await ensureStandalonePersonalProfile(trimmedWorkspaceId, cli: cli);

    final profileId = personal.id.trim();
    if (profileId.isNotEmpty) {
      await ProfileMcpLinkerService(fs: fs).syncForProfile(
        profileId: profileId,
        mcpServerIds: personal.bundle.mcpServerIds,
        catalog: await McpRepository().loadAll(),
        layout: layout,
      );
    }

    final paths = [
      for (final directory in trustedDirectories)
        if (directory.trim().isNotEmpty) directory.trim(),
    ];
    if (paths.isNotEmpty) {
      await WorkspaceTrustProvisioner(layout: layout, fs: fs).provisionWorkspace(
        workspaceId: trimmedWorkspaceId,
        directories: paths,
        tools: [cli.value],
      );
    }
  }

  /// Phase B (work fs): inheritance, plugins, skills, MCP — not config JSON bodies.
  Future<List<String>> applySessionFilesystem({
    required String workspaceId,
    required String sessionId,
    required PersonalProfile personal,
    CliTool cli = CliTool.claude,
    Map<String, Map<String, Object?>>? extraMcpServers,
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedWorkspaceId.isEmpty || trimmedSessionId.isEmpty) {
      return const [];
    }

    final warnings = <String>[];
    final personalProfileId = personal.id.trim();
    final standaloneScope = StandaloneLaunchProfileScope(
      workspaceId: trimmedWorkspaceId,
      sessionId: trimmedSessionId,
    );

    return _withStandaloneScope(standaloneScope, () async {
      String? sessionProvisionJson;
      await Future.wait([
        layout.ensureSessionRuntimeInheritsWorkspace(
          trimmedWorkspaceId,
          trimmedSessionId,
          cli.value,
        ),
        layout
            .provisionSessionPluginsFromIdentity(
              trimmedWorkspaceId,
              trimmedSessionId,
              personalProfileId,
              cli.value,
            )
            .then((json) => sessionProvisionJson = json),
      ]);

      final pluginProvisioner =
          _cliRegistry.capability<PluginProvisionerCapability>(cli);
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
            enabledPluginIds: personal.bundle.pluginIds,
            installedCatalog: await InstalledPluginCatalog.load(fs, basePath),
            layout: layout,
            tool: cli,
            memberProvisionJson: sessionProvisionJson,
          ),
        );
      }

      final provisionResult =
          await ResourceProvisioningService(
            fs: fs,
            registry: _cliRegistry,
          ).provisionForLaunch(
            scope: PersonalResourceScope(personal: personal),
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
      ).writeForStandaloneWorkspace(
        workspaceId: trimmedWorkspaceId,
        sessionId: trimmedSessionId,
        profileId: personalProfileId,
        extraServers: extraMcpServers,
      );

      return warnings;
    });
  }

  /// Phase B (control plane): session config JSON + env from CLI capabilities.
  Future<TeamLaunchOutcome> contributeSessionLaunch({
    required String workspaceId,
    required String sessionId,
    required String profileId,
    required PersonalProfile personal,
    String workingDirectory = '',
    List<String> additionalDirectories = const [],
    MemberBusIdleEndpoint? busIdle,
    CliPreset? preset,
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedWorkspaceId.isEmpty || trimmedSessionId.isEmpty) {
      return const TeamLaunchOutcome(environment: {});
    }

    final warnings = <String>[];
    await _infra.collectExtensionWarnings(
      warnings,
      teamId: profileId.trim(),
    );

    final cli = preset?.cli ?? CliTool.claude;
    final standaloneScope = StandaloneLaunchProfileScope(
      workspaceId: trimmedWorkspaceId,
      sessionId: trimmedSessionId,
    );
    final scope = LaunchProfileScope(
      workspaceId: trimmedWorkspaceId,
      teamId: trimmedWorkspaceId,
      sessionId: trimmedSessionId,
      cliTeamName: trimmedSessionId,
    );

    return _withStandaloneScope(standaloneScope, () async {
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
            personal: personal,
            standaloneScope: standaloneScope,
            members: const [],
            workingDirectory: workingDirectory,
            additionalDirectories: additionalDirectories,
            paths: this,
            catalog: catalog,
            busIdle: busIdle,
            preset: preset,
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
    });
  }

  /// Stages session launch mutations into [LaunchManifest] without touching the
  /// work filesystem. [readDelegate] supplies catalog reads (home or work).
  Future<({TeamLaunchOutcome outcome, LaunchManifest manifest})>
  stageSessionLaunch({
    required Filesystem readDelegate,
    required String workTeampilotRoot,
    required String workspaceId,
    required String sessionId,
    required String profileId,
    required PersonalProfile personal,
    String workingDirectory = '',
    List<String> additionalDirectories = const [],
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
    CliPreset? preset,
  }) async {
    final manifest = LaunchManifest(pathContext: readDelegate.pathContext);
    final stagingFs = ManifestFilesystem(
      manifest: manifest,
      readDelegate: readDelegate,
    );
    final staging = _stagingService(
      stagingFs: stagingFs,
      workTeampilotRoot: workTeampilotRoot,
    );

    final fsWarnings = await staging.applySessionFilesystem(
      workspaceId: workspaceId,
      sessionId: sessionId,
      personal: personal,
      cli: preset?.cli ?? CliTool.claude,
      extraMcpServers: extraMcpServers,
    );
    final outcome = await staging.contributeSessionLaunch(
      workspaceId: workspaceId,
      sessionId: sessionId,
      profileId: profileId,
      personal: personal,
      workingDirectory: workingDirectory,
      additionalDirectories: additionalDirectories,
      busIdle: busIdle,
      preset: preset,
    );
    return (
      outcome: TeamLaunchOutcome(
        environment: outcome.environment,
        warnings: [...fsWarnings, ...outcome.warnings],
      ),
      manifest: manifest,
    );
  }

  /// Phase B: full session launch — stage then flush to [fs].
  Future<TeamLaunchOutcome> prepareSessionLaunch({
    required String workspaceId,
    required String sessionId,
    required String profileId,
    required PersonalProfile personal,
    String workingDirectory = '',
    List<String> additionalDirectories = const [],
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
    CliPreset? preset,
    ManifestExecutor? manifestExecutor,
  }) async {
    final staged = await stageSessionLaunch(
      readDelegate: fs,
      workTeampilotRoot: basePath,
      workspaceId: workspaceId,
      sessionId: sessionId,
      profileId: profileId,
      personal: personal,
      workingDirectory: workingDirectory,
      additionalDirectories: additionalDirectories,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
      preset: preset,
    );
    final executor = manifestExecutor ?? const ManifestExecutor();
    await executor.flush(
      manifest: staged.manifest,
      targetFs: fs,
      sourceFs: fs,
    );
    return staged.outcome;
  }

  Future<T> _withStandaloneScope<T>(
    StandaloneLaunchProfileScope scope,
    Future<T> Function() action,
  ) async {
    if (_activeStandaloneScope != null) {
      return action();
    }
    _activeStandaloneScope = scope;
    try {
      return await action();
    } finally {
      _activeStandaloneScope = null;
    }
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

    final manifest = LaunchManifest(pathContext: readDelegate.pathContext);
    final stagingFs = ManifestFilesystem(
      manifest: manifest,
      readDelegate: readDelegate,
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
      memberId: memberId,
      extraMcpServers: extraMcpServers,
    );

    if (team != null) {
      final provisionResult =
          await ResourceProvisioningService(
            fs: stagingFs,
            registry: _cliRegistry,
          ).provisionForLaunch(
            scope: TeamResourceScope(team: team, member: launchMember),
            cli: launchCli,
            configDir: staging._launchResourceConfigDir(
              cli: launchCli,
              workspaceId: trimmedWorkspaceId,
              sessionId: trimmedSessionId,
              memberId: memberId,
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
      leadSessionId: leadSessionId,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
    );
    final executor = manifestExecutor ?? const ManifestExecutor();
    await executor.flush(
      manifest: staged.manifest,
      targetFs: fs,
      sourceFs: fs,
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
