import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cubits/app_provider_cubit.dart';
import '../cubits/app_update_cubit.dart';
import '../cubits/chat_cubit.dart';
import '../cubits/mailbox_cubit.dart';
import '../cubits/member_presence_cubit.dart';
import '../cubits/editor_cubit.dart';
import '../cubits/config_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/llm_config_cubit.dart';
import '../cubits/session_preferences_cubit.dart';
import '../cubits/extension_cubit.dart';
import '../cubits/mcp_cubit.dart';
import '../cubits/plugin_cubit.dart';
import '../cubits/skill_cubit.dart';
import '../repositories/mcp_repository.dart';
import '../services/mcp/team_mcp_linker_service.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../cubits/team_cubit.dart';
import '../cubits/team_hub_cubit.dart';
import '../models/connection_mode.dart';
import '../models/team_config.dart';
import '../models/windows_storage_backend.dart';
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
import '../repositories/team_repository.dart';
import '../router/app_router.dart';
import '../services/extension/builtin_manifests.dart';
import '../services/extension/extension_acquisition_engine.dart';
import '../services/extension/extension_provisioner.dart';
import '../services/storage/app_storage.dart';
import '../services/team/team_clone_service.dart';
import '../services/team_hub/git_registry_team_hub_source.dart';
import '../services/team_hub/team_hub_dependency_installers.dart';
import '../services/team_hub/team_hub_favorites_store.dart';
import '../services/cli/cli_tool_locator.dart';
import '../services/cli/registry/cli_tool_registry.dart';
import '../services/app/connection_mode_service.dart';
import '../services/cli/flashskyai_cli_locator.dart';
import '../services/storage/storage_resolver.dart';
import '../services/provider/provider_migration_service.dart';
import '../services/cli/remote_flashskyai_cli_locator.dart';
import '../services/storage/runtime_storage_context.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/skill/skill_fetch_service.dart';
import '../services/plugin/plugin_repo_disk_cache_service.dart';
import '../services/skill/skill_install_service.dart';
import '../services/skill/skill_manifest_service.dart';
import '../services/skill/skill_repo_disk_cache_service.dart';
import '../services/skill/skill_repo_git_service.dart';
import '../services/skill/skill_repo_service.dart';
import '../services/ssh/ssh_client_factory.dart';
import '../services/plugin/team_plugin_linker_service.dart';
import '../services/skill/team_skill_linker_service.dart';
import '../services/terminal/terminal_transport_factory.dart';
import '../utils/logger.dart';

/// Fully wired app dependencies produced after async bootstrap.
class AppShell {
  AppShell({
    required this.chatCubit,
    required this.memberPresenceCubit,
    required this.mailboxCubit,
    required this.editorCubit,
    required this.sessionRepo,
    required this.sshProfileRepo,
    required this.sshCredentialStore,
    required this.sshKnownHostRepo,
    required this.transportFactory,
    required this.sshClientFactory,
    required this.connectionModeService,
    required this.storageRoots,
    required this.teamCubit,
    required this.configCubit,
    required this.appProviderCubit,
    required this.llmConfigCubit,
    required this.layoutCubit,
    required this.sessionPreferencesCubit,
    required this.pluginCubit,
    required this.skillCubit,
    required this.mcpCubit,
    required this.teamHubCubit,
    required this.extensionCubit,
    required this.appUpdateCubit,
    required this.sshProfileCubit,
    required this.appSettings,
    required this.reinstallStorageContext,
    required this.bootstrapAppData,
    required this.cliToolRegistry,
  });

  final CliToolRegistry cliToolRegistry;
  final ChatCubit chatCubit;
  final MemberPresenceCubit memberPresenceCubit;
  final MailboxCubit mailboxCubit;
  final EditorCubit editorCubit;
  final SessionRepository sessionRepo;
  final SshProfileRepository sshProfileRepo;
  final SshCredentialStore sshCredentialStore;
  final SshKnownHostRepository sshKnownHostRepo;
  final TerminalTransportFactory transportFactory;
  final SshClientFactory sshClientFactory;
  final ConnectionModeService connectionModeService;
  final StorageRoots storageRoots;
  final TeamCubit teamCubit;
  final ConfigCubit configCubit;
  final AppProviderCubit appProviderCubit;
  final LlmConfigCubit llmConfigCubit;
  final LayoutCubit layoutCubit;
  final SessionPreferencesCubit sessionPreferencesCubit;
  final PluginCubit pluginCubit;
  final SkillCubit skillCubit;
  final McpCubit mcpCubit;
  final TeamHubCubit teamHubCubit;
  final ExtensionCubit extensionCubit;
  final AppUpdateCubit appUpdateCubit;
  final SshProfileCubit sshProfileCubit;
  final AppSettingsRepository appSettings;
  final Future<RuntimeStorageContext> Function() reinstallStorageContext;
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
  final cliLocated = locatedExecutables[CliTool.flashskyai];

  final appSettings = SharedPrefsAppSettingsRepository(preferences);
  final sessionPreferencesCubit = SessionPreferencesCubit(
    repository: SessionPreferencesRepository(preferences),
    locatedExecutable: cliLocated,
    locatedExecutables: locatedExecutables,
    cliToolRegistry: cliToolRegistry,
  );
  boot('loading session preferences');
  await sessionPreferencesCubit.load();
  boot('session preferences loaded');

  WindowsStorageBackend windowsStorageBackend() =>
      sessionPreferencesCubit.state.preferences.windowsStorageBackend;

  String? wslDistroFromPrefs() => RuntimeStorageContext.parseWslDistro(
    sessionPreferencesCubit.resolveExecutable(),
  );

  final sshCredentialStore = const SecureSshCredentialStore(
    FlutterSecureKeyValueStore(),
  );
  final sshKnownHostRepo = SharedPrefsSshKnownHostRepository(preferences);
  final sshClientFactory = SshClientFactory(
    credentialStore: sshCredentialStore,
    knownHostRepository: sshKnownHostRepo,
  );

  boot('resolving default project directory');
  final defaultProjectDirectory = await DefaultProjectDirectory.resolve();
  boot('installing RuntimeStorageContext');
  await RuntimeStorageContext.install(
    isSshMode:
        Platform.isAndroid ||
        sessionPreferencesCubit.state.preferences.connectionMode ==
            ConnectionMode.ssh,
    sshProfile: null,
    sshClientFactory: sshClientFactory,
    nativeAppDataPath: nativeAppDataPath,
    nativeHome:
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'],
    nativeCwd: defaultProjectDirectory,
    wslDistro: RuntimeStorageContext.parseWslDistro(cliLocated),
    windowsStorageBackend: windowsStorageBackend(),
  );
  boot(
    'RuntimeStorageContext installed '
    '(${RuntimeStorageContext.current.mode}, '
    'backend=${windowsStorageBackend().name}, '
    'root=${RuntimeStorageContext.current.appDataRoot})',
  );

  if (!Platform.isAndroid) {
    unawaited(
      ProviderMigrationService(cliExecutablePath: cliLocated).migrateIfNeeded(),
    );
  }

  final sshProfileRepo = SshProfileRepository();
  final remoteCliLocator = RemoteFlashskyaiCliLocator(
    clientFactory: sshClientFactory,
  );

  late final LlmConfigCubit llmConfigCubit;
  late final AppProviderCubit appProviderCubit;
  late final TeamCubit teamCubit;
  late final PluginCubit pluginCubit;
  late final SkillCubit skillCubit;
  late final McpCubit mcpCubit;
  late final TeamHubCubit teamHubCubit;
  late final ExtensionCubit extensionCubit;
  late final SessionRepository sessionRepo;
  late final ChatCubit chatCubit;
  late final MemberPresenceCubit memberPresenceCubit;
  late final EditorCubit editorCubit;
  late final StorageRoots storageRoots;
  late final SessionLifecycleService sessionLifecycleService;
  late final ConnectionModeService connectionModeService;
  late final Future<RuntimeStorageContext> Function() reinstallStorageContext;

  late final SshProfileCubit sshProfileCubit;
  sshProfileCubit = SshProfileCubit(
    profileRepository: sshProfileRepo,
    credentialStore: sshCredentialStore,
    locateRemoteCliPath: remoteCliLocator.locate,
    onRemoteCliLocated: (path) =>
        sessionPreferencesCubit.setCliExecutablePathFor(CliTool.claude, path),
    invalidateProfileConnection: sshClientFactory.disconnectProfile,
    enableRemoteCliDiscovery: () =>
        Platform.isAndroid &&
        sessionPreferencesCubit.state.preferences.connectionMode ==
            ConnectionMode.ssh,
    onActiveProfileChanged: () async {
      await reinstallStorageContext();
      storageRoots.invalidate();
      await reloadRemoteBackedAppData(
        storageRoots: storageRoots,
        llmConfigCubit: llmConfigCubit,
        appProviderCubit: appProviderCubit,
        teamCubit: teamCubit,
        pluginCubit: pluginCubit,
        skillCubit: skillCubit,
        mcpCubit: mcpCubit,
        chatCubit: chatCubit,
        sessionRepo: sessionRepo,
        sshProfileCubit: sshProfileCubit,
      );
    },
  );

  connectionModeService = ConnectionModeService(
    readPreferredMode: () =>
        sessionPreferencesCubit.state.preferences.connectionMode,
    hasSshProfiles: () => sshProfileCubit.state.hasProfiles,
  );

  reinstallStorageContext = () => RuntimeStorageContext.install(
    isSshMode: connectionModeService.isSshMode,
    sshProfile: sshProfileCubit.state.selectedProfile,
    sshClientFactory: sshClientFactory,
    nativeAppDataPath: nativeAppDataPath,
    nativeHome:
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'],
    nativeCwd: defaultProjectDirectory,
    wslDistro: wslDistroFromPrefs(),
    windowsStorageBackend: windowsStorageBackend(),
  );

  storageRoots = StorageRoots(
    isSshMode: () => connectionModeService.isSshMode,
    sshProfileResolver: () => sshProfileCubit.state.selectedProfile,
    reinstallContext: reinstallStorageContext,
  );

  final skillManifest = SkillManifestService(storageRoots: storageRoots);
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
    repos: SkillRepoService(storageRoots: storageRoots),
  );

  appProviderCubit = AppProviderCubit(
    flashskyaiExecutablePath: sessionPreferencesCubit.resolveExecutable,
    claudeExecutablePath: () =>
        sessionPreferencesCubit.resolveExecutable(CliTool.claude),
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

  sessionLifecycleService = SessionLifecycleService(
    llmConfigPathOverride: llmConfigPathOverrideForLaunch,
    storageRootsResolver: storageRoots.resolve,
    loadEnabledExtensionIds: ({teamId}) async {
      if (teamId != null && teamId.trim().isNotEmpty) {
        return extensionRepository.effectiveEnabledIds(teamId.trim());
      }
      return (await extensionRepository.load(forceReload: true)).globalEnabled;
    },
    cliToolRegistry: cliToolRegistry,
  );
  sessionRepo = SessionRepository(
    storageRoots: storageRoots,
    lifecycleService: sessionLifecycleService,
  );
  final teamRepo = TeamRepository(
    storageRoots: storageRoots,
    lifecycleService: sessionLifecycleService,
  );

  final pluginRepository = PluginRepository(storageRoots: storageRoots);
  final mcpRepository = McpRepository(storageRoots: storageRoots);
  teamCubit = TeamCubit(
    repository: teamRepo,
    sessionRepository: sessionRepo,
    reloadProjects: () => chatCubit.loadProjectData(sessionRepo),
    executableResolver: () => sessionPreferencesCubit.resolveExecutable(),
    cliExecutableResolver: sessionPreferencesCubit.resolveExecutable,
    llmConfigPathOverride: llmConfigPathOverrideForLaunch,
    storageRootsResolver: storageRoots.resolve,
    lifecycleService: sessionLifecycleService,
    skillLinker: TeamSkillLinkerService(storageRoots: storageRoots),
    installedSkillsLoader: () => skillRepo.loadInstalled(),
    pluginLinker: TeamPluginLinkerService(storageRoots: storageRoots),
    pluginRepository: pluginRepository,
    installedPluginsLoader: () => pluginRepository.loadAll(),
    mcpLinker: TeamMcpLinkerService(),
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
    diskCache: PluginRepoDiskCacheService(storageRoots: storageRoots),
    storageRoots: storageRoots,
    onPluginUninstalled: teamCubit.removePluginFromAllTeams,
    onPluginUpdated: teamCubit.syncTeamsUsingPlugin,
  );
  mcpCubit = McpCubit(
    mcpRepository,
    onMcpDeleted: teamCubit.removeMcpFromAllTeams,
  );

  final teamHubSource = GitRegistryTeamHubSource();
  final teamHubFavorites = TeamHubFavoritesStore();
  final pluginDiskCache = PluginRepoDiskCacheService(
    storageRoots: storageRoots,
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

  final appUpdateCubit = AppUpdateCubit();
  final layoutCubit = LayoutCubit(repository: LayoutRepository(preferences));
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
    connectionModeResolver: () => connectionModeService.effectiveMode,
    terminalScrollbackLinesResolver: () =>
        sessionPreferencesCubit.state.preferences.terminalScrollbackLines,
  );

  memberPresenceCubit = MemberPresenceCubit();
  chatCubit.bindPresenceCubit(memberPresenceCubit);

  final mailboxCubit =
      MailboxCubit(activeBus: () => chatCubit.activeTab?.teamBus);

  boot('loading layout');
  await layoutCubit.load();
  applyWorkspaceEntryMode(layoutCubit.state.preferences.workspaceEntryMode);
  boot('buildAppShell complete');

  Future<void> bootstrapAppData() async {
    await sshProfileCubit.load(notifyActiveProfileChanged: false);
    if (connectionModeService.isSshMode &&
        sshProfileCubit.state.selectedProfile != null) {
      await reinstallStorageContext();
      storageRoots.invalidate();
    }
    await reloadRemoteBackedAppData(
      storageRoots: storageRoots,
      llmConfigCubit: llmConfigCubit,
      appProviderCubit: appProviderCubit,
      teamCubit: teamCubit,
      pluginCubit: pluginCubit,
      skillCubit: skillCubit,
      mcpCubit: mcpCubit,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
      sshProfileCubit: sshProfileCubit,
    );
  }

  editorCubit = EditorCubit();

  return AppShell(
    cliToolRegistry: cliToolRegistry,
    chatCubit: chatCubit,
    memberPresenceCubit: memberPresenceCubit,
    mailboxCubit: mailboxCubit,
    editorCubit: editorCubit,
    sessionRepo: sessionRepo,
    sshProfileRepo: sshProfileRepo,
    sshCredentialStore: sshCredentialStore,
    sshKnownHostRepo: sshKnownHostRepo,
    transportFactory: transportFactory,
    sshClientFactory: sshClientFactory,
    connectionModeService: connectionModeService,
    storageRoots: storageRoots,
    teamCubit: teamCubit,
    configCubit: configCubit,
    appProviderCubit: appProviderCubit,
    llmConfigCubit: llmConfigCubit,
    layoutCubit: layoutCubit,
    sessionPreferencesCubit: sessionPreferencesCubit,
    pluginCubit: pluginCubit,
    skillCubit: skillCubit,
    mcpCubit: mcpCubit,
    teamHubCubit: teamHubCubit,
    extensionCubit: extensionCubit,
    appUpdateCubit: appUpdateCubit,
    sshProfileCubit: sshProfileCubit,
    appSettings: appSettings,
    reinstallStorageContext: reinstallStorageContext,
    bootstrapAppData: bootstrapAppData,
  );
}

Future<void> reloadRemoteBackedAppData({
  required StorageRoots storageRoots,
  required LlmConfigCubit llmConfigCubit,
  required AppProviderCubit appProviderCubit,
  required TeamCubit teamCubit,
  required PluginCubit pluginCubit,
  required SkillCubit skillCubit,
  required McpCubit mcpCubit,
  required ChatCubit chatCubit,
  required SessionRepository sessionRepo,
  required SshProfileCubit sshProfileCubit,
}) async {
  await storageRoots.resolve();
  await Future.wait([
    llmConfigCubit.load(),
    appProviderCubit.load(),
    teamCubit.load(),
    pluginCubit.load(),
    skillCubit.loadAll(),
    mcpCubit.loadAll(),
    chatCubit.loadProjectData(sessionRepo),
    sshProfileCubit.load(notifyActiveProfileChanged: false),
  ]);
  await teamCubit.syncSelectedTeamSkills(installed: skillCubit.state.installed);
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
    final repo = SessionPreferencesRepository(widget.preferences);
    final prefs = await repo.load();
    await repo.save(
      prefs.copyWith(windowsStorageBackend: WindowsStorageBackend.native),
    );
    await _start();
  }

  bool get _canFallbackToNativeStorage {
    if (!Platform.isWindows || _error == null) return false;
    try {
      final raw = widget.preferences.getString(
        SessionPreferencesRepository.storageKey,
      );
      if (raw == null || raw.isEmpty) return true;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return true;
      return WindowsStorageBackendJson.fromJson(
            decoded['windowsStorageBackend'] as String?,
          ) ==
          WindowsStorageBackend.wsl;
    } on Object {
      return true;
    }
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
