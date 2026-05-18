import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'cubits/app_provider_cubit.dart';
import 'cubits/chat_cubit.dart';
import 'cubits/config_cubit.dart';
import 'cubits/layout_cubit.dart';
import 'cubits/llm_config_cubit.dart';
import 'cubits/session_preferences_cubit.dart';
import 'cubits/skill_cubit.dart';
import 'cubits/ssh_profile_cubit.dart';
import 'cubits/team_cubit.dart';
import 'l10n/l10n_extensions.dart';
import 'repositories/app_settings_repository.dart';
import 'repositories/layout_repository.dart';
import 'repositories/session_preferences_repository.dart';
import 'repositories/session_repository.dart';
import 'repositories/skill_repository.dart';
import 'repositories/ssh_credential_store.dart';
import 'repositories/ssh_known_host_repository.dart';
import 'repositories/ssh_profile_repository.dart';
import 'repositories/team_repository.dart';
import 'router/app_router.dart';
import 'models/connection_mode.dart';
import 'models/team_config.dart';
import 'services/app_storage.dart';
import 'services/cli_tool_locator.dart';
import 'services/connection_mode_service.dart';
import 'services/flashskyai_storage_roots.dart';
import 'services/remote_cli_session_checker.dart';
import 'services/remote_ssh_storage_paths.dart';
import 'services/skill_repo_service.dart';
import 'services/skill_install_service.dart';
import 'services/skill_manifest_service.dart';
import 'services/terminal_fonts.dart';
import 'services/flashskyai_cli_locator.dart';
import 'services/remote_flashskyai_cli_locator.dart';
import 'services/ssh_client_factory.dart';
import 'services/provider_migration_service.dart';
import 'services/team_skill_linker_service.dart';
import 'services/temp_team_cleaner.dart';
import 'services/terminal_transport_factory.dart';
import 'theme/app_theme.dart';
import 'widgets/ui_warmup.dart';

class _CleanupWindowListener extends WindowListener {
  _CleanupWindowListener(this.chatCubit);
  final ChatCubit chatCubit;

  @override
  void onWindowClose() {
    unawaited(_shutdownAndDestroy());
  }

  Future<void> _shutdownAndDestroy() async {
    try {
      await chatCubit.close();
    } finally {
      await windowManager.destroy();
    }
  }
}

/// [BlocProvider.value] does not call [ChatCubit.close]; dispose here covers
/// hot restart and other cases where the widget tree tears down.
class _AppShutdownScope extends StatefulWidget {
  const _AppShutdownScope({required this.chatCubit, required this.child});

  final ChatCubit chatCubit;
  final Widget child;

  @override
  State<_AppShutdownScope> createState() => _AppShutdownScopeState();
}

class _AppShutdownScopeState extends State<_AppShutdownScope> {
  @override
  void dispose() {
    unawaited(widget.chatCubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await loadBundledTerminalFonts();

  if (!Platform.isAndroid) {
    await windowManager.ensureInitialized();
    final windowRect = await windowManager.getBounds();
    WindowOptions windowOptions = WindowOptions(
      size: Size(
        (windowRect.width > 400) ? windowRect.width : 1200,
        (windowRect.height > 300) ? windowRect.height : 700,
      ),
      minimumSize: const Size(800, 500),
      center: false,
      title: 'TeamPilot',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  await AppStorage.init();

  final preferences = await SharedPreferences.getInstance();
  final locatedExecutables = <TeamCli, String>{};
  if (!Platform.isAndroid) {
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
  await AppStorage.useWslCliDataDirIfNeeded(cliLocated);

  if (!Platform.isAndroid) {
    await windowManager.setPreventClose(true);
  }
  final appSettings = SharedPrefsAppSettingsRepository(preferences);
  final homeDirectory =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  if (!Platform.isAndroid) {
    await ProviderMigrationService(
      homeDirectory: homeDirectory,
      currentDirectory: Directory.current.path,
      cliExecutablePath: cliLocated,
    ).migrateIfNeeded();
  }

  final sessionPreferencesCubit = SessionPreferencesCubit(
    repository: SessionPreferencesRepository(preferences),
    locatedExecutable: cliLocated,
    locatedExecutables: locatedExecutables,
  );

  // SSH infrastructure (Android + future desktop)
  final sshProfileRepo = SshProfileRepository();
  final sshCredentialStore = const SecureSshCredentialStore(
    FlutterSecureKeyValueStore(),
  );
  final sshKnownHostRepo = SharedPrefsSshKnownHostRepository(preferences);
  final sshClientFactory = SshClientFactory(
    credentialStore: sshCredentialStore,
    knownHostRepository: sshKnownHostRepo,
  );
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

  final sshProfileCubit = SshProfileCubit(
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
      storageRoots.invalidate();
      await _reloadRemoteBackedAppData(
        storageRoots: storageRoots,
        llmConfigCubit: llmConfigCubit,
        appProviderCubit: appProviderCubit,
        teamCubit: teamCubit,
        skillCubit: skillCubit,
        chatCubit: chatCubit,
        sessionRepo: sessionRepo,
      );
    },
  );

  final connectionModeService = ConnectionModeService(
    readPreferredMode: () =>
        sessionPreferencesCubit.state.preferences.connectionMode,
    hasSshProfiles: () => sshProfileCubit.state.hasProfiles,
  );

  storageRoots = FlashskyaiStorageRoots(
    isSshMode: () => connectionModeService.isSshMode,
    sshProfileResolver: () => sshProfileCubit.state.selectedProfile,
    sshClientFactory: sshClientFactory,
    remotePathResolver: RemoteSshStoragePathResolver(
      clientFactory: sshClientFactory,
    ),
  );

  sessionRepo = SessionRepository(storageRoots: storageRoots);
  final remoteCliSessionChecker = RemoteCliSessionChecker(storageRoots);
  final tempTeamCleaner = TempTeamCleaner(storageRoots: storageRoots);

  final teamRepo = TeamRepository(storageRoots: storageRoots);
  final skillManifest = SkillManifestService(storageRoots: storageRoots);
  final skillRepo = SkillRepository(
    manifest: skillManifest,
    install: SkillInstallService(manifest: skillManifest),
    repos: SkillRepoService(storageRoots: storageRoots),
  );

  appProviderCubit = AppProviderCubit();

  llmConfigCubit = LlmConfigCubit(
    appSettings: appSettings,
    currentDirectory: Directory.current.path,
    homeDirectory: homeDirectory,
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

  teamCubit = TeamCubit(
    repository: teamRepo,
    executableResolver: () => sessionPreferencesCubit.resolveExecutable(),
    cliExecutableResolver: sessionPreferencesCubit.resolveExecutable,
    llmConfigPathOverride: llmConfigPathOverrideForLaunch,
    storageRootsResolver: storageRoots.resolve,
    skillLinker: TeamSkillLinkerService(storageRoots: storageRoots),
    installedSkillsLoader: () => skillRepo.loadInstalled(),
  );
  skillCubit = SkillCubit(
    skillRepo,
    onSkillUninstalled: teamCubit.removeSkillFromAllTeams,
  );
  final layoutCubit = LayoutCubit(repository: LayoutRepository(preferences));

  final transportFactory = TerminalTransportFactory(
    sshProfileRepository: sshProfileRepo,
    sshCredentialStore: sshCredentialStore,
    sshKnownHostRepository: sshKnownHostRepo,
    sshClientFactory: sshClientFactory,
  );

  chatCubit = ChatCubit(
    sessionRepository: sessionRepo,
    tempTeamCleaner: tempTeamCleaner,
    cliSessionDescriptorExists: remoteCliSessionChecker.exists,
    llmConfigPathOverride: llmConfigPathOverrideForLaunch,
    storageRootsResolver: storageRoots.resolve,
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
  final configCubit = ConfigCubit();

  await sessionPreferencesCubit.load();
  await layoutCubit.load();

  if (!Platform.isAndroid) {
    windowManager.addListener(_CleanupWindowListener(chatCubit));
  }

  runApp(
    _AppShutdownScope(
      chatCubit: chatCubit,
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<SessionRepository>.value(value: sessionRepo),
          RepositoryProvider<SshProfileRepository>.value(value: sshProfileRepo),
          RepositoryProvider<SshCredentialStore>.value(
            value: sshCredentialStore,
          ),
          RepositoryProvider<SshKnownHostRepository>.value(
            value: sshKnownHostRepo,
          ),
          RepositoryProvider<TerminalTransportFactory>.value(
            value: transportFactory,
          ),
          RepositoryProvider<SshClientFactory>.value(value: sshClientFactory),
          RepositoryProvider<ConnectionModeService>.value(
            value: connectionModeService,
          ),
          RepositoryProvider<FlashskyaiStorageRoots>.value(value: storageRoots),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: teamCubit),
            BlocProvider.value(value: chatCubit),
            BlocProvider.value(value: configCubit),
            BlocProvider.value(value: appProviderCubit),
            BlocProvider.value(value: llmConfigCubit),
            BlocProvider.value(value: layoutCubit),
            BlocProvider.value(value: sessionPreferencesCubit),
            BlocProvider.value(value: skillCubit),
            BlocProvider.value(value: sshProfileCubit),
          ],
          child: const TeamPilotApp(),
        ),
      ),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      _bootstrapAppData(
        storageRoots: storageRoots,
        tempTeamCleaner: tempTeamCleaner,
        sshProfileCubit: sshProfileCubit,
        llmConfigCubit: llmConfigCubit,
        appProviderCubit: appProviderCubit,
        teamCubit: teamCubit,
        skillCubit: skillCubit,
        chatCubit: chatCubit,
        sessionRepo: sessionRepo,
      ),
    );
  });
}

Future<void> _reloadRemoteBackedAppData({
  required FlashskyaiStorageRoots storageRoots,
  required LlmConfigCubit llmConfigCubit,
  required AppProviderCubit appProviderCubit,
  required TeamCubit teamCubit,
  required SkillCubit skillCubit,
  required ChatCubit chatCubit,
  required SessionRepository sessionRepo,
}) async {
  // One SSH connect + path resolve; shared SFTP for all readers below.
  await storageRoots.resolve();
  await Future.wait([
    llmConfigCubit.load(),
    appProviderCubit.load(),
    teamCubit.load(),
    skillCubit.loadAll(),
    chatCubit.loadProjectData(sessionRepo),
  ]);
  await teamCubit.syncSelectedTeamSkills(installed: skillCubit.state.installed);
}

Future<void> _bootstrapAppData({
  required FlashskyaiStorageRoots storageRoots,
  required TempTeamCleaner tempTeamCleaner,
  required SshProfileCubit sshProfileCubit,
  required LlmConfigCubit llmConfigCubit,
  required AppProviderCubit appProviderCubit,
  required TeamCubit teamCubit,
  required SkillCubit skillCubit,
  required ChatCubit chatCubit,
  required SessionRepository sessionRepo,
}) async {
  await sshProfileCubit.load(notifyActiveProfileChanged: false);
  storageRoots.invalidate();
  await Future.wait([
    tempTeamCleaner.cleanup(),
    _reloadRemoteBackedAppData(
      storageRoots: storageRoots,
      llmConfigCubit: llmConfigCubit,
      appProviderCubit: appProviderCubit,
      teamCubit: teamCubit,
      skillCubit: skillCubit,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
    ),
  ]);
}

class TeamPilotApp extends StatelessWidget {
  const TeamPilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      LayoutCubit,
      LayoutState,
      (String themeMode, String colorPreset, String locale)
    >(
      selector: (state) {
        final prefs = state.preferences;
        var themeMode = prefs.themeMode;
        if (themeMode != 'light' &&
            themeMode != 'dark' &&
            themeMode != 'system') {
          themeMode = 'system';
        }
        return (
          themeMode,
          normalizeThemeColorPreset(prefs.themeColorPreset),
          prefs.locale,
        );
      },
      builder: (context, themePrefs) {
        final (themeMode, colorPreset, savedLocale) = themePrefs;

        ThemeMode themeModeFromPrefs(String mode) => switch (mode) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };

        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'TeamPilot',
          theme: buildLightTheme(colorPreset),
          darkTheme: buildDarkTheme(colorPreset),
          themeMode: themeModeFromPrefs(themeMode),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: savedLocale.isNotEmpty ? Locale(savedLocale) : null,
          builder: (context, child) =>
              UiWarmup(child: child ?? const SizedBox.shrink()),
          localeResolutionCallback: (locale, supportedLocales) {
            if (savedLocale.isNotEmpty) return Locale(savedLocale);
            for (final supportedLocale in supportedLocales) {
              if (supportedLocale.languageCode == locale?.languageCode) {
                return supportedLocale;
              }
            }
            return const Locale('en');
          },
          routerConfig: appRouter,
        );
      },
    );
  }
}
