import 'package:path/path.dart' as p;

import '../../models/cli_preset.dart';
import '../../models/extension_manifest.dart';
import '../../models/personal_identity.dart';
import '../../models/skill.dart';
import '../../models/team_config.dart';
import '../storage/runtime_layout.dart';
import '../extension/extension_detector.dart';
import '../host/host_execution_environment.dart';
import '../host/host_script_dialect.dart';
import '../host/script_file_hook_provisioner.dart';
import '../cli/registry/capabilities/config_profile_capability.dart';
import '../cli/registry/capabilities/plugin_manifest_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../io/filesystem.dart';
import '../mcp/mcp_registry_service.dart';
import '../plugin/cli_plugin_registry_service.dart';
import '../resource/resource_provisioning_service.dart';
import '../resource/resource_scope.dart';
import '../team/claude_team_roster_service.dart';
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
  static final _defaultCliRegistry = CliToolRegistry.builtIn();

  ConfigProfileService({
    required String basePath,
    String? home,
    Filesystem? fs,
    RuntimeLayout? layout,
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
       _cliRegistry = cliRegistry ?? _defaultCliRegistry,
       _loadInstalledSkills = loadInstalledSkills;

  final ConfigProfileInfrastructure _infra;
  final CliToolRegistry _cliRegistry;
  final Future<List<Skill>> Function()? _loadInstalledSkills;
  StandaloneLaunchProfileScope? _activeStandaloneScope;

  Future<ResourceCatalog> _skillCatalog() async {
    final skills =
        await (_loadInstalledSkills?.call() ?? Future.value(const <Skill>[]));
    return ResourceCatalog(
      skills: skills,
      skillsRoot: AppPaths.skillsDirForTeampilotRoot(basePath),
      pathContext: fs.pathContext,
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
    TeamIdentity? team,
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
    final pluginManifest = _cliRegistry.capability<PluginManifestCapability>(
      cli,
    );
    if (pluginManifest?.supportsPluginRegistry == true) {
      await CliPluginRegistryService(
        fs: fs,
        teampilotRoot: basePath,
        layout: layout,
        cliRegistry: _cliRegistry,
      ).writeForSession(
        workspaceId: trimmedWorkspaceId,
        teamId: trimmedTeamId,
        sessionId: trimmedSessionId,
        tool: cli,
        team: team,
        memberId: memberId,
        memberProvisionJson: memberProvisionJson,
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

  Future<void> ensureStandalonePersonalIdentity(
    String workspaceId, {
    CliTool cli = CliTool.claude,
  }) async {
    final trimmed = workspaceId.trim();
    if (trimmed.isEmpty) return;
    await layout.ensureWorkspaceConfigInheritsApp(trimmed, cli.value);
  }

  Future<void> ensureStandaloneSessionProfile(
    String workspaceId,
    String sessionId, {
    CliTool cli = CliTool.claude,
    PersonalIdentity? personal,
    Map<String, Map<String, Object?>>? extraMcpServers,
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedWorkspaceId.isEmpty || trimmedSessionId.isEmpty) return;

    final standaloneScope = StandaloneLaunchProfileScope(
      workspaceId: trimmedWorkspaceId,
      sessionId: trimmedSessionId,
    );
    await _withStandaloneScope(standaloneScope, () async {
      await ensureStandalonePersonalIdentity(trimmedWorkspaceId, cli: cli);
      String? sessionProvisionJson;
      await Future.wait([
        layout.ensureSessionRuntimeInheritsWorkspace(
          trimmedWorkspaceId,
          trimmedSessionId,
          cli.value,
        ),
        layout
            .provisionSessionPluginsFromWorkspace(
              trimmedWorkspaceId,
              trimmedSessionId,
              cli.value,
            )
            .then((json) => sessionProvisionJson = json),
      ]);
      final pluginManifest = _cliRegistry.capability<PluginManifestCapability>(
        cli,
      );
      if (pluginManifest?.supportsPluginRegistry == true) {
        await CliPluginRegistryService(
          fs: fs,
          teampilotRoot: basePath,
          layout: layout,
          cliRegistry: _cliRegistry,
        ).writeForStandaloneSession(
          workspaceId: trimmedWorkspaceId,
          sessionId: trimmedSessionId,
          tool: cli,
          personal: personal,
          memberProvisionJson: sessionProvisionJson,
        );
      }
      final cap = _cliRegistry.capability<ConfigProfileCapability>(cli);
      if (cap != null) {
        await cap.ensureSessionProfile(
          ConfigProfileSessionContext(
            workspaceId: trimmedWorkspaceId,
            teamId: '',
            sessionId: trimmedSessionId,
            members: const [],
            paths: this,
            standaloneScope: standaloneScope,
            personal: personal,
          ),
        );
      }
      await McpRegistryService(
        fs: fs,
        layout: layout,
      ).writeForStandaloneWorkspace(
        workspaceId: trimmedWorkspaceId,
        sessionId: trimmedSessionId,
        extraServers: extraMcpServers,
      );
    });
  }

  Future<TeamLaunchOutcome> prepareWorkspaceLaunch({
    required String workspaceId,
    required String sessionId,
    required String identityId,
    required PersonalIdentity personal,
    String workingDirectory = '',
    List<String> additionalDirectories = const [],
    Map<String, Map<String, Object?>>? extraMcpServers,
    String? busIdleUrl,
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
      teamId: identityId.trim(),
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
      await ensureStandaloneSessionProfile(
        trimmedWorkspaceId,
        trimmedSessionId,
        cli: cli,
        personal: personal,
        extraMcpServers: extraMcpServers,
      );

      final provisionResult =
          await ResourceProvisioningService(
            fs: fs,
            registry: _cliRegistry,
          ).provisionForLaunch(
            scope: PersonalResourceScope(personal: personal),
            cli: cli,
            configDir: layout.sessionRuntimeToolDir(
              trimmedWorkspaceId,
              trimmedSessionId,
              cli.value,
            ),
            catalog: await _skillCatalog(),
          );
      warnings.addAll(provisionResult.warnings);

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
            busIdleUrl: busIdleUrl,
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
    TeamIdentity? team,
    String? leadSessionId,
    Map<String, Map<String, Object?>>? extraMcpServers,
    String? busIdleUrl,
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
      return const TeamLaunchOutcome(environment: {});
    }

    final warnings = <String>[];
    await _infra.collectExtensionWarnings(warnings, teamId: trimmedTeamId);

    String? memberId;
    if (team?.teamMode == TeamMode.mixed && member != null && member.isValid) {
      memberId = ClaudeTeamRosterService.safeClaudePathSegment(member.id);
    }

    final scope = resolveLaunchProfileScope(
      workspaceId: trimmedWorkspaceId,
      teamId: trimmedTeamId,
      appSessionId: trimmedSessionId,
      cliTeamName: cliTeamName,
      memberId: memberId,
    );

    await ensureSessionProfile(
      trimmedWorkspaceId,
      trimmedSessionId,
      trimmedTeamId,
      cli: cli,
      team: team,
      memberId: memberId,
      extraMcpServers: extraMcpServers,
    );

    if (team != null) {
      final provisionResult =
          await ResourceProvisioningService(
            fs: fs,
            registry: _cliRegistry,
          ).provisionForLaunch(
            scope: TeamResourceScope(team: team, member: member),
            cli: cli,
            configDir: layout.sessionRuntimeToolDir(
              trimmedWorkspaceId,
              trimmedSessionId,
              cli.value,
              memberId: memberId,
            ),
            catalog: await _skillCatalog(),
          );
      warnings.addAll(provisionResult.warnings);
    }

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
          memberId: memberId,
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

  @override
  Future<Map<String, Object?>> readMetadataFile(
    String path,
    Map<String, Object?> defaults,
  ) => _infra.readMetadataFile(path, defaults);

  @override
  Future<void> writeJsonIfChanged(String path, Map<String, Object?> value) =>
      _infra.writeJsonIfChanged(path, value);

  @override
  Future<Map<String, Object?>> metadataWithTrustedWorkspaces({
    required String metadataPath,
    required Map<String, Object?> defaultMetadata,
    required Map<String, Object?> defaultWorkspaceConfig,
    required Iterable<String> directories,
  }) => _infra.metadataWithTrustedWorkspaces(
    metadataPath: metadataPath,
    defaultMetadata: defaultMetadata,
    defaultWorkspaceConfig: defaultWorkspaceConfig,
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
