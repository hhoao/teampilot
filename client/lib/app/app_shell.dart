import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cubits/app_provider_cubit.dart';
import '../cubits/app_update_cubit.dart';
import '../cubits/chat_cubit.dart';
import '../cubits/config_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/llm_config_cubit.dart';
import '../cubits/session_preferences_cubit.dart';
import '../cubits/skill_cubit.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../cubits/team_cubit.dart';
import '../models/connection_mode.dart';
import '../models/team_config.dart';
import '../models/windows_storage_backend.dart';
import '../l10n/app_localizations.dart';
import '../repositories/app_settings_repository.dart';
import '../repositories/layout_repository.dart';
import '../repositories/session_preferences_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/skill_repository.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_known_host_repository.dart';
import '../repositories/ssh_profile_repository.dart';
import '../repositories/team_repository.dart';
import '../services/cli_tool_locator.dart';
import '../services/connection_mode_service.dart';
import '../services/flashskyai_cli_locator.dart';
import '../services/flashskyai_storage_roots.dart';
import '../services/provider_migration_service.dart';
import '../services/remote_flashskyai_cli_locator.dart';
import '../services/runtime_storage_context.dart';
import '../services/session_lifecycle_service.dart';
import '../services/skill_fetch_service.dart';
import '../services/skill_install_service.dart';
import '../services/skill_manifest_service.dart';
import '../services/skill_repo_disk_cache_service.dart';
import '../services/skill_repo_git_service.dart';
import '../services/skill_repo_service.dart';
import '../services/ssh_client_factory.dart';
import '../services/team_skill_linker_service.dart';
import '../services/terminal_transport_factory.dart';
import '../utils/logger.dart';

/// Fully wired app dependencies produced after async bootstrap.
class AppShell {
  AppShell({
    required this.chatCubit,
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
    required this.skillCubit,
    required this.appUpdateCubit,
    required this.sshProfileCubit,
    required this.reinstallStorageContext,
    required this.bootstrapAppData,
  });

  final ChatCubit chatCubit;
  final SessionRepository sessionRepo;
  final SshProfileRepository sshProfileRepo;
  final SshCredentialStore sshCredentialStore;
  final SshKnownHostRepository sshKnownHostRepo;
  final TerminalTransportFactory transportFactory;
  final SshClientFactory sshClientFactory;
  final ConnectionModeService connectionModeService;
  final FlashskyaiStorageRoots storageRoots;
  final TeamCubit teamCubit;
  final ConfigCubit configCubit;
  final AppProviderCubit appProviderCubit;
  final LlmConfigCubit llmConfigCubit;
  final LayoutCubit layoutCubit;
  final SessionPreferencesCubit sessionPreferencesCubit;
  final SkillCubit skillCubit;
  final AppUpdateCubit appUpdateCubit;
  final SshProfileCubit sshProfileCubit;
  final Future<RuntimeStorageContext> Function() reinstallStorageContext;
  final Future<void> Function() bootstrapAppData;
}

Future<AppShell> buildAppShell({
  required SharedPreferences preferences,
  required String nativeAppDataPath,
}) async {
  void boot(String phase) => appLogger.i('[boot] $phase');

  boot('start');
  final locatedExecutables = <TeamCli, String>{};
  if (!Platform.isAndroid) {
    boot('locating CLI tools');
    final flashskyaiLocated = await FlashskyaiCliLocator.locate();
    if (flashskyaiLocated != null && flashskyaiLocated.isNotEmpty) {
      locatedExecutables[TeamCli.flashskyai] = flashskyaiLocated;
    }
    final claudeLocated = await const CliToolLocator('claude').locate();
    if (claudeLocated != null && claudeLocated.isNotEmpty) {
      locatedExecutables[TeamCli.claude] = claudeLocated;
    }
  }
  final cliLocated = locatedExecutables[TeamCli.flashskyai];

  final appSettings = SharedPrefsAppSettingsRepository(preferences);
  final sessionPreferencesCubit = SessionPreferencesCubit(
    repository: SessionPreferencesRepository(preferences),
    locatedExecutable: cliLocated,
    locatedExecutables: locatedExecutables,
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
    nativeCwd: Directory.current.path,
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
      ProviderMigrationService(
        cliExecutablePath: cliLocated,
      ).migrateIfNeeded(),
    );
  }

  final sshProfileRepo = SshProfileRepository();
  final remoteCliLocator = RemoteFlashskyaiCliLocator(
    clientFactory: sshClientFactory,
  );

  late final LlmConfigCubit llmConfigCubit;
  late final AppProviderCubit appProviderCubit;
  late final TeamCubit teamCubit;
  late final SkillCubit skillCubit;
  late final SessionRepository sessionRepo;
  late final ChatCubit chatCubit;
  late final FlashskyaiStorageRoots storageRoots;
  late final SessionLifecycleService sessionLifecycleService;
  late final ConnectionModeService connectionModeService;
  late final Future<RuntimeStorageContext> Function() reinstallStorageContext;

  late final SshProfileCubit sshProfileCubit;
  sshProfileCubit = SshProfileCubit(
    profileRepository: sshProfileRepo,
    credentialStore: sshCredentialStore,
    locateRemoteCliPath: remoteCliLocator.locate,
    onRemoteCliLocated: sessionPreferencesCubit.setCliExecutablePath,
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
        skillCubit: skillCubit,
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
    nativeCwd: Directory.current.path,
    wslDistro: wslDistroFromPrefs(),
    windowsStorageBackend: windowsStorageBackend(),
  );

  storageRoots = FlashskyaiStorageRoots(
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

  sessionLifecycleService = SessionLifecycleService(
    llmConfigPathOverride: llmConfigPathOverrideForLaunch,
    storageRootsResolver: storageRoots.resolve,
  );
  sessionRepo = SessionRepository(
    storageRoots: storageRoots,
    lifecycleService: sessionLifecycleService,
  );
  final teamRepo = TeamRepository(
    storageRoots: storageRoots,
    lifecycleService: sessionLifecycleService,
  );

  teamCubit = TeamCubit(
    repository: teamRepo,
    executableResolver: () => sessionPreferencesCubit.resolveExecutable(),
    cliExecutableResolver: sessionPreferencesCubit.resolveExecutable,
    llmConfigPathOverride: llmConfigPathOverrideForLaunch,
    storageRootsResolver: storageRoots.resolve,
    lifecycleService: sessionLifecycleService,
    skillLinker: TeamSkillLinkerService(storageRoots: storageRoots),
    installedSkillsLoader: () => skillRepo.loadInstalled(),
  );
  skillCubit = SkillCubit(
    skillRepo,
    onSkillUninstalled: teamCubit.removeSkillFromAllTeams,
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
  );

  boot('loading layout');
  await layoutCubit.load();
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
      skillCubit: skillCubit,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
      sshProfileCubit: sshProfileCubit,
    );
  }

  return AppShell(
    chatCubit: chatCubit,
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
    skillCubit: skillCubit,
    appUpdateCubit: appUpdateCubit,
    sshProfileCubit: sshProfileCubit,
    reinstallStorageContext: reinstallStorageContext,
    bootstrapAppData: bootstrapAppData,
  );
}

Future<void> reloadRemoteBackedAppData({
  required FlashskyaiStorageRoots storageRoots,
  required LlmConfigCubit llmConfigCubit,
  required AppProviderCubit appProviderCubit,
  required TeamCubit teamCubit,
  required SkillCubit skillCubit,
  required ChatCubit chatCubit,
  required SessionRepository sessionRepo,
  required SshProfileCubit sshProfileCubit,
}) async {
  await storageRoots.resolve();
  await Future.wait([
    llmConfigCubit.load(),
    appProviderCubit.load(),
    teamCubit.load(),
    skillCubit.loadAll(),
    chatCubit.loadProjectData(sessionRepo),
    sshProfileCubit.load(notifyActiveProfileChanged: false),
  ]);
  await teamCubit.syncSelectedTeamSkills(installed: skillCubit.state.installed);
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
      appLogger.e('[boot] buildAppShell failed', error: error, stackTrace: stackTrace);
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
                          onPressed:
                              _retrying ? null : _switchToNativeStorageAndRetry,
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
