import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cubits/app_provider_cubit.dart';
import '../cubits/app_update_cubit.dart';
import '../cubits/chat_cubit.dart';
import '../services/team_bus/remote/remote_bus_binding_resolver.dart';
import '../services/team_bus/remote/ssh_remote_bus_mount_factory.dart';
import '../services/remote/remote_member_preflight_factory.dart';
import '../cubits/board_cubit.dart';
import '../cubits/mailbox_cubit.dart';
import '../cubits/member_presence_cubit.dart';
import '../cubits/notification_cubit.dart';
import '../cubits/editor_cubit.dart';
import '../cubits/ai_feature_settings_cubit.dart';
import '../cubits/config_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/workspace_tools_cubit.dart';
import '../cubits/llm_config_cubit.dart';
import '../cubits/session_preferences_cubit.dart';
import '../cubits/extension_cubit.dart';
import '../cubits/mcp_cubit.dart';
import '../cubits/plugin_cubit.dart';
import '../repositories/launch_profile_repository.dart';
import '../services/storage/launch_profile_provisioner.dart';
import '../services/team/default_workspace_service.dart';
import '../cubits/cli_presets_cubit.dart';
import '../repositories/cli_presets_repository.dart';
import '../cubits/skill_cubit.dart';
import '../repositories/mcp_repository.dart';
import '../services/mcp/profile_mcp_linker_service.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../cubits/launch_profile_cubit.dart';
import '../cubits/team_hub_cubit.dart';
import '../models/connection_mode.dart';
import '../models/runtime_target.dart';
import '../models/ssh_profile.dart';
import '../models/team_config.dart';
import '../l10n/app_localizations.dart';
import '../repositories/app_settings_repository.dart';
import '../repositories/layout_repository.dart';
import '../repositories/session_preferences_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/plugin_repository.dart';
import '../repositories/skill_repository.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_known_host_repository.dart';
import '../repositories/ssh_profile_repository.dart';
import '../repositories/extension_repository.dart';
import '../router/app_router.dart';
import '../services/extension/builtin_manifests.dart';
import '../services/extension/extension_acquisition_engine.dart';
import '../services/extension/extension_provisioner.dart';
import '../services/storage/app_storage.dart';
import '../services/team/team_clone_service.dart';
import '../services/team_hub/composite_team_hub_source.dart';
import '../services/team_hub/git_registry_team_hub_source.dart';
import '../services/team_hub/team_hub_dependency_installers.dart';
import '../services/team_hub/team_hub_favorites_store.dart';
import '../services/cli/cli_tool_locator.dart';
import '../services/cli/registry/cli_bootstrap.dart';
import '../services/cli/registry/cli_tool_registry.dart';
import '../services/provider/claude/claude_provider_credentials_service.dart';
import '../services/provider/codex/codex_provider_credentials_service.dart';
import '../services/provider/opencode/opencode_provider_credentials_service.dart';
import '../services/provider/cursor/cursor_agent_models_service.dart';
import '../services/provider/cursor/cursor_provider_credentials_service.dart';
import '../services/app/connection_mode_service.dart';
import '../services/cli/flashskyai_cli_locator.dart';
import '../services/provider/provider_migration_service.dart';
import '../services/cli/remote_cli_locator.dart';
import '../services/storage/runtime_context.dart';
import '../services/storage/runtime_context_resolver.dart';
import '../services/storage/runtime_context_registry.dart';
import '../services/storage/home_target_controller.dart';
import '../services/storage/home_target_store.dart';
import '../services/storage/runtime_target_registry.dart';
import '../services/storage/targets_repository.dart';
import '../services/notification/notification_recorder.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/skill/skill_fetch_service.dart';
import '../services/plugin/plugin_repo_disk_cache_service.dart';
import '../services/skill/skill_install_service.dart';
import '../services/skill/skill_manifest_service.dart';
import '../services/skill/skill_repo_disk_cache_service.dart';
import '../services/skill/skill_repo_git_service.dart';
import '../services/skill/skill_repo_service.dart';
import '../services/ssh/ssh_client_factory.dart';
import '../services/plugin/profile_plugin_linker_service.dart';
import '../services/terminal/terminal_transport_factory.dart';
import '../services/file_tree/workspace_file_tree_store.dart';
import '../services/git/git_repo_store.dart';
import '../services/terminal/workspace_terminal_registry.dart';
import '../utils/logger.dart';

/// Fully wired app dependencies produced after async bootstrap.
class AppShell {
  AppShell({
    required this.homeTargetController,
    required this.chatCubit,
    required this.memberPresenceCubit,
    required this.mailboxCubit,
    required this.boardCubit,
    required this.notificationCubit,
    required this.editorCubit,
    required this.sessionRepo,
    required this.sshProfileRepo,
    required this.sshCredentialStore,
    required this.sshKnownHostRepo,
    required this.transportFactory,
    required this.workspaceTerminalRegistry,
    required this.gitRepoStore,
    required this.workspaceFileTreeStore,
    required this.sshClientFactory,
    required this.connectionModeService,
    required this.identityRepository,
    required this.teamCubit,
    required this.configCubit,
    required this.appProviderCubit,
    required this.llmConfigCubit,
    required this.layoutCubit,
    required this.workspaceToolsCubit,
    required this.sessionPreferencesCubit,
    required this.pluginCubit,
    required this.cliPresetsCubit,
    required this.skillCubit,
    required this.mcpCubit,
    required this.teamHubCubit,
    required this.extensionCubit,
    required this.appUpdateCubit,
    required this.sshProfileCubit,
    required this.appSettings,
    required this.aiFeatureSettingsCubit,
    required this.reinstallStorageContext,
    required this.bootstrapAppData,
    required this.cliToolRegistry,
  });

  final CliToolRegistry cliToolRegistry;
  final HomeTargetController homeTargetController;
  final ChatCubit chatCubit;
  final MemberPresenceCubit memberPresenceCubit;
  final MailboxCubit mailboxCubit;
  final BoardCubit boardCubit;
  final NotificationCubit notificationCubit;
  final EditorCubit editorCubit;
  final SessionRepository sessionRepo;
  final SshProfileRepository sshProfileRepo;
  final SshCredentialStore sshCredentialStore;
  final SshKnownHostRepository sshKnownHostRepo;
  final TerminalTransportFactory transportFactory;
  final WorkspaceTerminalRegistry workspaceTerminalRegistry;
  final GitRepoStore gitRepoStore;
  final WorkspaceFileTreeStore workspaceFileTreeStore;
  final SshClientFactory sshClientFactory;
  final ConnectionModeService connectionModeService;
  final LaunchProfileRepository identityRepository;
  final LaunchProfileCubit teamCubit;
  final ConfigCubit configCubit;
  final AppProviderCubit appProviderCubit;
  final LlmConfigCubit llmConfigCubit;
  final LayoutCubit layoutCubit;
  final WorkspaceToolsCubit workspaceToolsCubit;
  final SessionPreferencesCubit sessionPreferencesCubit;
  final PluginCubit pluginCubit;
  final CliPresetsCubit cliPresetsCubit;
  final SkillCubit skillCubit;
  final McpCubit mcpCubit;
  final TeamHubCubit teamHubCubit;
  final ExtensionCubit extensionCubit;
  final AppUpdateCubit appUpdateCubit;
  final SshProfileCubit sshProfileCubit;
  final AppSettingsRepository appSettings;
  final AiFeatureSettingsCubit aiFeatureSettingsCubit;
  final Future<void> Function() reinstallStorageContext;
  final Future<void> Function() bootstrapAppData;
}

Future<AppShell> buildAppShell({
  required SharedPreferences preferences,
  required String nativeAppDataPath,
}) async {
  void boot(String phase) => appLogger.i('[boot] $phase');

  boot('start');
  final cliToolRegistry = CliToolRegistry.builtIn();
  final locatedExecutables = <CliTool, String>{};
  if (!Platform.isAndroid) {
    boot('locating CLI tools');
    final flashskyaiLocated = await FlashskyaiCliLocator.locate();
    if (flashskyaiLocated != null && flashskyaiLocated.isNotEmpty) {
      locatedExecutables[CliTool.flashskyai] = flashskyaiLocated;
    }
    final claudeLocated = await const CliToolLocator('claude').locate();
    if (claudeLocated != null && claudeLocated.isNotEmpty) {
      locatedExecutables[CliTool.claude] = claudeLocated;
    }
  }
  final claudeLocated = locatedExecutables[CliTool.claude];
  final flashskyaiLocated = locatedExecutables[CliTool.flashskyai];

  final appSettings = SharedPrefsAppSettingsRepository(preferences);
  final aiFeatureSettingsCubit = AiFeatureSettingsCubit(repository: appSettings);
  unawaited(aiFeatureSettingsCubit.load());
  final sessionPreferencesCubit = SessionPreferencesCubit(
    repository: SessionPreferencesRepository(preferences),
    locatedExecutables: locatedExecutables,
    cliToolRegistry: cliToolRegistry,
  );
  boot('loading session preferences');
  await sessionPreferencesCubit.load();
  boot('session preferences loaded');

  final sshCredentialStore = const SecureSshCredentialStore(
    FlutterSecureKeyValueStore(),
  );
  final sshKnownHostRepo = SharedPrefsSshKnownHostRepository(preferences);
  final sshClientFactory = SshClientFactory(
    credentialStore: sshCredentialStore,
    knownHostRepository: sshKnownHostRepo,
  );

  // P1: the home target (the machine the control plane runs on) is the single
  // authority, stored device-local in HomeTargetStore. distro/profile are
  // encoded in the id; there is no connectionMode/windowsStorageBackend knob.
  final homeTargetStore = HomeTargetStore(preferences);
  RuntimeTarget homeTargetFromId(String id) => switch (runtimeKindOfId(id)) {
    RuntimeKind.ssh => RuntimeTarget.ssh(sshProfileIdOfId(id) ?? '', label: 'SSH'),
    RuntimeKind.wsl => RuntimeTarget.wsl(wslDistroOfId(id) ?? ''),
    RuntimeKind.local => RuntimeTarget.local(),
  };
  // Stored id wins; otherwise platform default. Desktop home is always local
  // (Windows can pick wsl in the picker); Android with no stored ssh home falls
  // to local and is held at the create-profile gate until a home is chosen.
  var homeTarget = homeTargetFromId(homeTargetStore.load());
  RuntimeTarget defaultTargetResolver() => homeTarget;

  boot('resolving default workspace directory');
  final defaultWorkspaceDirectory = await DefaultWorkspaceDirectory.resolve();

  final sshProfileRepo = SshProfileRepository();
  final remoteCliLocator = RemoteCliLocator(registry: cliToolRegistry);
  // Android home-ssh discovery of the remote flashskyai binary (used as the
  // claude executable path). Generalized P3c locator behind the same adapter.
  Future<String?> locateRemoteCli(SshProfile profile) async {
    try {
      final client = await sshClientFactory.clientFor(profile);
      return remoteCliLocator.resolve(
        cli: CliTool.flashskyai,
        run: RemoteCliLocator.runnerForClient(client),
      );
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[remote-cli] locate failed for ${profile.hostIdentifier}: $error',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  late final LlmConfigCubit llmConfigCubit;
  late final AppProviderCubit appProviderCubit;
  late final LaunchProfileCubit teamCubit;
  late final PluginCubit pluginCubit;
  late final LaunchProfileRepository identityRepository;
  late final LaunchProfileProvisioner identityProvisioner;
  late final CliPresetsCubit cliPresetsCubit;
  late final SkillCubit skillCubit;
  late final McpCubit mcpCubit;
  late final TeamHubCubit teamHubCubit;
  late final ExtensionCubit extensionCubit;
  late final SessionRepository sessionRepo;
  late final ChatCubit chatCubit;
  late final MemberPresenceCubit memberPresenceCubit;
  late final EditorCubit editorCubit;
  late final SessionLifecycleService sessionLifecycleService;
  late final ConnectionModeService connectionModeService;
  late final Future<void> Function() reinstallStorageContext;

  late final SshProfileCubit sshProfileCubit;
  sshProfileCubit = SshProfileCubit(
    profileRepository: sshProfileRepo,
    credentialStore: sshCredentialStore,
    locateRemoteCliPath: locateRemoteCli,
    onRemoteCliLocated: (path) =>
        sessionPreferencesCubit.setCliExecutablePathFor(CliTool.claude, path),
    invalidateProfileConnection: sshClientFactory.disconnectProfile,
    enableRemoteCliDiscovery: () =>
        Platform.isAndroid &&
        defaultTargetResolver().kind == RuntimeKind.ssh,
    onActiveProfileChanged: () async {
      await reinstallStorageContext();
      await reloadRemoteBackedAppData(
        llmConfigCubit: llmConfigCubit,
        appProviderCubit: appProviderCubit,
        teamCubit: teamCubit,
        pluginCubit: pluginCubit,
        skillCubit: skillCubit,
        mcpCubit: mcpCubit,
        extensionCubit: extensionCubit,
        chatCubit: chatCubit,
        sessionRepo: sessionRepo,
        sshProfileCubit: sshProfileCubit,
      );
    },
  );

  // P1: targets.json is a pure target catalog (no default/migrate); the home
  // target authority is the device-local homeTargetStore read above. The
  // registry is used by the picker UI to list selectable targets.
  final targetsRepo = TargetsRepository();
  final runtimeTargetRegistry = RuntimeTargetRegistry(
    repo: targetsRepo,
    sshProfileRepo: sshProfileRepo,
    isWindows: Platform.isWindows,
    isAndroid: Platform.isAndroid,
  );

  SshProfile? sshProfileById(String id) =>
      sshProfileCubit.state.profiles.where((p) => p.id == id).firstOrNull;

  // P2: de-singleton. One resolver + a per-target context registry. The home
  // context (control plane) is materialized once and pushed onto AppStorage;
  // work-plane contexts are resolved lazily per workspace target id.
  final runtimeContextResolver = RuntimeContextResolver(
    sshClientFactory: sshClientFactory,
    nativeAppDataPath: nativeAppDataPath,
    nativeHome:
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'],
    nativeCwd: defaultWorkspaceDirectory,
  );
  final runtimeContextRegistry = RuntimeContextRegistry(
    resolver: runtimeContextResolver,
    homeTarget: defaultTargetResolver(),
    sshProfileById: sshProfileById,
    onEvict: (targetId) async {
      final pid = sshProfileIdOfId(targetId);
      if (pid != null) sshClientFactory.disconnectProfile(pid);
    },
  );
  boot('installing home runtime context');
  await runtimeContextRegistry.ensureHome();
  AppStorage.bindHome(runtimeContextRegistry.home());
  boot(
    'home context installed '
    '(${AppStorage.context.mode}, home=${homeTarget.id}, '
    'root=${AppStorage.appDataRoot})',
  );

  if (!Platform.isAndroid) {
    unawaited(
      ProviderMigrationService(
        cliExecutablePath: flashskyaiLocated,
      ).migrateIfNeeded(),
    );
  }

  // Persists the chosen home id, rebinds the registry home, and republishes it
  // on AppStorage.
  Future<void> setHomeTarget(String id) async {
    await homeTargetStore.save(id);
    homeTarget = homeTargetFromId(id);
    await runtimeContextRegistry.dispose(id);
    await runtimeContextRegistry.rebindHome(homeTarget);
    AppStorage.bindHome(runtimeContextRegistry.home());
  }

  connectionModeService = ConnectionModeService(
    defaultTargetResolver: defaultTargetResolver,
    hasSshProfiles: () => sshProfileCubit.state.hasProfiles,
  );

  // Re-resolve the home context (e.g. after an ssh profile's details change):
  // evict the cached context for the home id, rebind, republish.
  reinstallStorageContext = () async {
    await runtimeContextRegistry.dispose(defaultTargetResolver().id);
    await runtimeContextRegistry.rebindHome(defaultTargetResolver());
    AppStorage.bindHome(runtimeContextRegistry.home());
  };

  cliToolRegistry.configure(
    CliBootstrap(
      cursorAgentModelsService: CursorAgentModelsService(
      ),
      claudeCredentialsService: ClaudeProviderCredentialsService(
        fs: AppStorage.fs,
        basePath: AppStorage.paths.basePath,
        resolveClaudeExecutable: () =>
            sessionPreferencesCubit.resolveExecutable(CliTool.claude),
      ),
      cursorCredentialsService: CursorProviderCredentialsService(
        fs: AppStorage.fs,
        basePath: AppStorage.paths.basePath,
        resolveCursorExecutable: () =>
            sessionPreferencesCubit.resolveExecutable(CliTool.cursor),
      ),
      codexCredentialsService: CodexProviderCredentialsService(
        fs: AppStorage.fs,
        basePath: AppStorage.paths.basePath,
        resolveCodexExecutable: () =>
            sessionPreferencesCubit.resolveExecutable(CliTool.codex),
      ),
      opencodeCredentialsService: OpencodeProviderCredentialsService(
        fs: AppStorage.fs,
        basePath: AppStorage.paths.basePath,
        resolveOpencodeExecutable: () =>
            sessionPreferencesCubit.resolveExecutable(CliTool.opencode),
      ),
    ),
  );

  final skillManifest = SkillManifestService();
  final skillGit = SkillRepoGitService();
  final skillFetch = SkillFetchService(git: skillGit);
  final skillRepoCache = SkillRepoDiskCacheService(fetch: skillFetch);
  final skillRepo = SkillRepository(
    manifest: skillManifest,
    fetch: skillFetch,
    repoCache: skillRepoCache,
    install: SkillInstallService(
      manifest: skillManifest,
      fetch: skillFetch,
      repoCache: skillRepoCache,
    ),
    repos: SkillRepoService(),
  );

  appProviderCubit = AppProviderCubit(
    flashskyaiExecutablePath: sessionPreferencesCubit.resolveExecutable,
    claudeExecutablePath: () =>
        sessionPreferencesCubit.resolveExecutable(CliTool.claude),
    cursorExecutablePath: () =>
        sessionPreferencesCubit.resolveExecutable(CliTool.cursor),
  );

  llmConfigCubit = LlmConfigCubit(
    appSettings: appSettings,
    executableResolver: () => sessionPreferencesCubit.resolveExecutable(),
    isSshMode: () => connectionModeService.isSshMode,
    sshProfileResolver: () => sshProfileCubit.state.selectedProfile,
    sshClientFactory: sshClientFactory,
    sshWorkingDirectoryResolver: () =>
        sessionPreferencesCubit.state.preferences.defaultSshWorkingDirectory,
  );

  String? llmConfigPathOverrideForLaunch() {
    final s = llmConfigCubit.state;
    final path = s.effectiveConfigPath.trim();
    if (path.isEmpty) return null;
    if (connectionModeService.isSshMode) return path;
    return s.isUsingCustomPath ? path : null;
  }

  final extensionRepository = ExtensionRepository(
    fs: AppStorage.fs,
    stateFilePath: AppStorage.paths.extensionsStateJson,
    manifests: builtInExtensionManifests(),
  );
  extensionCubit = ExtensionCubit(
    extensionRepository,
    ExtensionAcquisitionEngine(),
  );

  identityRepository = LaunchProfileRepository();

  final cliPresetsRepo = CliPresetsRepository(
    fs: AppStorage.fs,
    presetsPath: AppStorage.paths.cliPresetsJson,
  );
  sessionLifecycleService = SessionLifecycleService(
    llmConfigPathOverride: llmConfigPathOverrideForLaunch,
    storageRootsResolver: () async => AppStorage.context,
    // P2: launch resolves the work-plane on the workspace's target machine.
    workContextResolver: runtimeContextRegistry.forTarget,
    loadEnabledExtensionIds: ({teamId, workspaceId}) async {
      final trimmedTeamId = teamId?.trim() ?? '';
      if (trimmedTeamId.isNotEmpty) {
        return extensionRepository.effectiveEnabledIds(trimmedTeamId);
      }
      final trimmedWorkspaceId = workspaceId?.trim() ?? '';
      if (trimmedWorkspaceId.isNotEmpty) {
        return extensionRepository.effectiveEnabledIds(
          LaunchProfileProvisioner.defaultPersonalId,
        );
      }
      return (await extensionRepository.load(forceReload: true)).globalEnabled;
    },
    cliToolRegistry: cliToolRegistry,
    identityRepository: identityRepository,
    loadInstalledSkills: () => skillRepo.loadInstalled(),
    cliPresetsRepository: cliPresetsRepo,
    loadPresets: () => cliPresetsCubit.state.presets,
  );
  sessionRepo = SessionRepository(
    lifecycleService: sessionLifecycleService,
  );
  final pluginRepository = PluginRepository();
  final mcpRepository = McpRepository();
  identityProvisioner = LaunchProfileProvisioner(repository: identityRepository);
  teamCubit = LaunchProfileCubit(
    repository: identityRepository,
    sessionRepository: sessionRepo,
    identityProvisioner: identityProvisioner,
    executableResolver: () => sessionPreferencesCubit.resolveExecutable(),
    cliExecutableResolver: sessionPreferencesCubit.resolveExecutable,
    llmConfigPathOverride: llmConfigPathOverrideForLaunch,
    storageRootsResolver: () async => AppStorage.context,
    lifecycleService: sessionLifecycleService,
    pluginLinker: ProfilePluginLinkerService(),
    pluginRepository: pluginRepository,
    installedPluginsLoader: () => pluginRepository.loadAll(),
    mcpLinker: ProfileMcpLinkerService(),
    mcpRepository: mcpRepository,
    installedMcpLoader: () => mcpRepository.loadAll(),
    extensionMcpContributor: (teamId) async {
      final enabled = await extensionRepository.effectiveEnabledIds(teamId);
      final provisioner = ExtensionProvisioner(
        manifests: builtInExtensionManifests(),
        isEnabled: (id) async => enabled.contains(id),
      );
      return provisioner.collectMcpContributions();
    },
  );
  skillCubit = SkillCubit(
    skillRepo,
    onSkillUninstalled: teamCubit.removeSkillFromAllTeams,
  );
  pluginCubit = PluginCubit(
    repository: pluginRepository,
    installService: pluginRepository.install,
    repoService: pluginRepository.repos,
    diskCache: PluginRepoDiskCacheService(),
    onPluginUninstalled: teamCubit.removePluginFromAllTeams,
    onPluginUpdated: teamCubit.syncTeamsUsingPlugin,
  );
  cliPresetsCubit = CliPresetsCubit(repository: cliPresetsRepo);
  unawaited(cliPresetsCubit.load());
  mcpCubit = McpCubit(
    mcpRepository,
    onMcpDeleted: teamCubit.removeMcpFromAllTeams,
  );

  final teamHubSource = CompositeTeamHubSource.withDefaults(
    GitRegistryTeamHubSource(),
  );
  final teamHubFavorites = TeamHubFavoritesStore();
  final pluginDiskCache = PluginRepoDiskCacheService(
  );
  final teamCloneService = TeamCloneService(
    installSkill: skillInstallerFor(skillRepo.install),
    installPlugin: pluginInstallerFor(
      pluginRepository.install,
      pluginDiskCache,
    ),
    installMcp: mcpInstallerFor(mcpRepository),
    createTeam:
        ({
          required name,
          required cli,
          required teamMode,
          required members,
          required skillIds,
          required pluginIds,
          required mcpServerIds,
          required description,
          required extraArgs,
        }) => teamCubit.addClonedTeam(
          name: name,
          cli: cli,
          teamMode: teamMode,
          members: members,
          skillIds: skillIds,
          pluginIds: pluginIds,
          mcpServerIds: mcpServerIds,
          description: description,
          extraArgs: extraArgs,
        ),
  );
  teamHubCubit = TeamHubCubit(
    source: teamHubSource,
    loadFavorites: teamHubFavorites.load,
    saveFavoriteToggle: teamHubFavorites.toggle,
    cloneTeam: teamCloneService.clone,
    loadInstalledDepIds: () async {
      final skills = await skillRepo.loadInstalled();
      final plugins = await pluginRepository.loadAll();
      final mcps = await mcpRepository.loadAll();
      return <String>{
        ...skills.map((s) => s.id),
        ...plugins.map((p) => p.id),
        ...mcps.map((m) => m.id),
      };
    },
  );

  final appUpdateCubit = AppUpdateCubit(settings: appSettings);
  final layoutCubit = LayoutCubit(repository: LayoutRepository(preferences));
  final workspaceToolsCubit = WorkspaceToolsCubit();
  final workspaceTerminalRegistry = WorkspaceTerminalRegistry();
  final gitRepoStore = GitRepoStore();
  final workspaceFileTreeStore = WorkspaceFileTreeStore();
  final configCubit = ConfigCubit();

  final transportFactory = TerminalTransportFactory(
    sshProfileRepository: sshProfileRepo,
    sshCredentialStore: sshCredentialStore,
    sshKnownHostRepository: sshKnownHostRepo,
    sshClientFactory: sshClientFactory,
  );

  chatCubit = ChatCubit(
    sessionRepository: sessionRepo,
    lifecycleService: sessionLifecycleService,
    autoLaunchAllMembersOnConnect: () =>
        sessionPreferencesCubit.state.preferences.autoLaunchAllMembersOnConnect,
    executableResolver: () => sessionPreferencesCubit.resolveExecutable(),
    cliExecutableResolver: sessionPreferencesCubit.resolveExecutable,
    transportFactory: transportFactory,
    sshProfileResolver: () => sshProfileCubit.state.selectedProfile,
    sshDefaultWorkingDirectoryResolver: () =>
        sessionPreferencesCubit.state.preferences.defaultSshWorkingDirectory,
    sshUseLoginShellResolver: () =>
        sessionPreferencesCubit.state.preferences.sshUseLoginShell,
    defaultTargetResolver: defaultTargetResolver,
    terminalScrollbackLinesResolver: () =>
        sessionPreferencesCubit.state.preferences.terminalScrollbackLines,
    // P3b (#1): connect remote (ssh) mixed-team members back to the in-process
    // bus over a reverse tunnel. Local members resolve to null (unchanged).
    remoteBusResolver: RemoteBusBindingResolver(
      registry: cliToolRegistry,
      mountFactory: sshRemoteBusMountFactory(
        sshClientFactory: sshClientFactory,
        profileById: (id) async => sshProfileById(id),
        contextForTarget: runtimeContextRegistry.forTarget,
      ),
    ),
    // P3c: members on a machine other than home run preflight (connect → CLI
    // ready → app-data materialize) before launch. SSH/SFTP ops are on-device.
    remoteMemberPreflight: buildRemoteMemberPreflightCoordinator(
      registry: cliToolRegistry,
      sshClientFactory: sshClientFactory,
      profileById: sshProfileById,
      contextForTarget: runtimeContextRegistry.forTarget,
      homeContext: runtimeContextRegistry.home,
      homeTarget: defaultTargetResolver,
      isCredentialOptIn: targetsRepo.isCredentialOptIn,
      isInstallOptIn: targetsRepo.isInstallOptIn,
      cliPathOverride: targetsRepo.cliPathOverride,
      // on-device: real per-CLI credential export + skills/plugins linking +
      // relay provisioning + install execution compose over the work transport.
      loadLocalCredentials: (_) async => const [],
    ),
  );

  memberPresenceCubit = MemberPresenceCubit();
  chatCubit.bindPresenceCubit(memberPresenceCubit);

  final mailboxCubit =
      MailboxCubit(activeBus: () => chatCubit.activeTab?.teamBus);

  final boardCubit =
      BoardCubit(activeBus: () => chatCubit.activeTab?.teamBus);

  final notificationCubit = NotificationCubit();
  await notificationCubit.load();
  NotificationRecorder.install(notificationCubit);

  boot('loading layout');
  await layoutCubit.load();
  applyWorkspaceEntryMode(
    layoutCubit.state.preferences.workspaceEntryMode,
    lastOpenedWorkspaceId: layoutCubit.state.preferences.lastOpenedWorkspaceId,
  );
  boot('buildAppShell complete');

  Future<void> bootstrapAppData() async {
    await sshProfileCubit.load(notifyActiveProfileChanged: false);
    // Home is ssh and its profile is now loaded → reinstall the home context
    // against the real remote (the first install fell back to native).
    final homeSshProfileId = defaultTargetResolver().sshProfileId;
    if (connectionModeService.isSshMode &&
        homeSshProfileId != null &&
        sshProfileById(homeSshProfileId) != null) {
      await reinstallStorageContext();
    }
    await reloadRemoteBackedAppData(
      llmConfigCubit: llmConfigCubit,
      appProviderCubit: appProviderCubit,
      teamCubit: teamCubit,
      pluginCubit: pluginCubit,
      skillCubit: skillCubit,
      mcpCubit: mcpCubit,
      extensionCubit: extensionCubit,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
      sshProfileCubit: sshProfileCubit,
    );
    reapplyWorkspaceEntryFromPreferences(
      layoutCubit.state.preferences,
      knownWorkspaceIds: {
        for (final workspace in chatCubit.state.workspaces) workspace.workspaceId,
      },
    );
  }

  editorCubit = EditorCubit();

  // P1: switching the home target persists the id, rebinds the home context,
  // then reinstalls + reloads all remote-backed app data (same chain the old
  // backend/profile switches used).
  Future<void> switchHomeTarget(String id) async {
    await setHomeTarget(id); // persists + rebinds home + republishes AppStorage
    await reloadRemoteBackedAppData(
      llmConfigCubit: llmConfigCubit,
      appProviderCubit: appProviderCubit,
      teamCubit: teamCubit,
      pluginCubit: pluginCubit,
      skillCubit: skillCubit,
      mcpCubit: mcpCubit,
      extensionCubit: extensionCubit,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
      sshProfileCubit: sshProfileCubit,
    );
  }

  final homeTargetController = HomeTargetController(
    registry: runtimeTargetRegistry,
    current: defaultTargetResolver,
    switchTo: switchHomeTarget,
  );

  return AppShell(
    cliToolRegistry: cliToolRegistry,
    homeTargetController: homeTargetController,
    chatCubit: chatCubit,
    memberPresenceCubit: memberPresenceCubit,
    mailboxCubit: mailboxCubit,
    boardCubit: boardCubit,
    notificationCubit: notificationCubit,
    editorCubit: editorCubit,
    sessionRepo: sessionRepo,
    sshProfileRepo: sshProfileRepo,
    sshCredentialStore: sshCredentialStore,
    sshKnownHostRepo: sshKnownHostRepo,
    transportFactory: transportFactory,
    workspaceTerminalRegistry: workspaceTerminalRegistry,
    gitRepoStore: gitRepoStore,
    workspaceFileTreeStore: workspaceFileTreeStore,
    sshClientFactory: sshClientFactory,
    connectionModeService: connectionModeService,
    identityRepository: identityRepository,
    teamCubit: teamCubit,
    configCubit: configCubit,
    appProviderCubit: appProviderCubit,
    llmConfigCubit: llmConfigCubit,
    layoutCubit: layoutCubit,
    workspaceToolsCubit: workspaceToolsCubit,
    sessionPreferencesCubit: sessionPreferencesCubit,
    pluginCubit: pluginCubit,
    cliPresetsCubit: cliPresetsCubit,
    skillCubit: skillCubit,
    mcpCubit: mcpCubit,
    teamHubCubit: teamHubCubit,
    extensionCubit: extensionCubit,
    appUpdateCubit: appUpdateCubit,
    sshProfileCubit: sshProfileCubit,
    appSettings: appSettings,
    aiFeatureSettingsCubit: aiFeatureSettingsCubit,
    reinstallStorageContext: reinstallStorageContext,
    bootstrapAppData: bootstrapAppData,
  );
}

Future<void> reloadRemoteBackedAppData({
  required LlmConfigCubit llmConfigCubit,
  required AppProviderCubit appProviderCubit,
  required LaunchProfileCubit teamCubit,
  required PluginCubit pluginCubit,
  required SkillCubit skillCubit,
  required McpCubit mcpCubit,
  required ExtensionCubit extensionCubit,
  required ChatCubit chatCubit,
  required SessionRepository sessionRepo,
  required SshProfileCubit sshProfileCubit,
}) async {
  await Future.wait([
    llmConfigCubit.load(),
    appProviderCubit.load(),
    teamCubit.load(),
    pluginCubit.load(),
    skillCubit.loadAll(),
    mcpCubit.loadAll(),
    extensionCubit.load(force: true),
    sshProfileCubit.load(notifyActiveProfileChanged: false),
  ]);
  final defaultTeam = teamCubit.state.teams
      .where((t) => t.id == LaunchProfileProvisioner.defaultTeamId)
      .firstOrNull;
  if (defaultTeam != null) {
    await DefaultWorkspaceService.seed(sessionRepo, defaultTeam: defaultTeam);
  }
  await chatCubit.loadWorkspaceData(sessionRepo);
  await teamCubit.syncSelectedTeamPlugins(
    installed: pluginCubit.state.installed,
  );
  await teamCubit.syncSelectedTeamMcp(installed: mcpCubit.state.servers);
}

class TeamPilotBootstrap extends StatefulWidget {
  const TeamPilotBootstrap({
    super.key,
    required this.preferences,
    required this.nativeAppDataPath,
    required this.childBuilder,
  });

  final SharedPreferences preferences;
  final String nativeAppDataPath;
  final Widget Function(AppShell shell) childBuilder;

  @override
  State<TeamPilotBootstrap> createState() => _TeamPilotBootstrapState();
}

class _TeamPilotBootstrapState extends State<TeamPilotBootstrap> {
  AppShell? _shell;
  Object? _error;
  var _retrying = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      appLogger.i('[boot] TeamPilotBootstrap starting buildAppShell');
      final shell = await buildAppShell(
        preferences: widget.preferences,
        nativeAppDataPath: widget.nativeAppDataPath,
      );
      if (!mounted) return;
      setState(() {
        _shell = shell;
        _error = null;
        _retrying = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(shell.bootstrapAppData());
      });
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[boot] buildAppShell failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _error = error;
        _retrying = false;
      });
    }
  }

  Future<void> _switchToNativeStorageAndRetry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    // Home target failed to install (e.g. WSL unavailable) — fall back to the
    // local device as home and retry bootstrap.
    await HomeTargetStore(widget.preferences).save(RuntimeTarget.localId);
    await _start();
  }

  bool get _canFallbackToNativeStorage {
    if (!Platform.isWindows || _error == null) return false;
    return runtimeKindOfId(HomeTargetStore(widget.preferences).load()) ==
        RuntimeKind.wsl;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) {
                final l10n = AppLocalizations.of(context);
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.bootstrapStartupFailed(_error.toString())),
                      if (_canFallbackToNativeStorage) ...[
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _retrying
                              ? null
                              : _switchToNativeStorageAndRetry,
                          child: _retrying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(l10n.bootstrapUseNativeStorageInstead),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
    }
    final shell = _shell;
    if (shell == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Starting TeamPilot…'),
              ],
            ),
          ),
        ),
      );
    }
    return widget.childBuilder(shell);
  }
}
