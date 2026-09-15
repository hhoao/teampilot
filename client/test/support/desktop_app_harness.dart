import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/app/ui_zoom_baseline.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/ai_feature_settings_cubit.dart';
import 'package:teampilot/cubits/ai_history_cubit.dart';
import 'package:teampilot/cubits/app_bootstrap_cubit.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/config_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/extension_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/llm_config_cubit.dart';
import 'package:teampilot/cubits/managed_provider_cubit.dart';
import 'package:teampilot/cubits/managed_provider_usage_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/notification_cubit.dart';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/cubits/repo_clone_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/cubits/ssh_connection_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/services/workbench/workbench_chat_bridge.dart';
import 'package:teampilot/cubits/workspace_tools_cubit.dart';
import 'package:teampilot/main.dart';
import 'package:teampilot/models/llm_config.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/pages/home_workspace/workspace_chrome_commands.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_usage_repository.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/repositories/extension_repository.dart';
import 'package:teampilot/repositories/plugin_repository.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/repositories/workspace_project_config_repository.dart';
import 'package:teampilot/router/app_router.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/run_command_registrar.dart';
import 'package:teampilot/services/commands/workspace_search_command_registrar.dart';
import 'package:teampilot/services/commands/workspace_content_search_command_registrar.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/services/search/workspace_search_indexes.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';
import 'package:teampilot/services/extension/builtin_manifests.dart';
import 'package:teampilot/services/extension/extension_acquisition_engine.dart';
import 'package:teampilot/services/extension/extension_detector.dart';
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';
import 'package:teampilot/services/expert_hub/expert_hub_catalog.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import 'package:teampilot/services/file_tree/workspace_file_tree_store.dart';
import 'package:teampilot/services/git/git_command_runner.dart';
import 'package:teampilot/services/git/git_repo_store.dart';
import 'package:teampilot/services/home_workspace/home_workspace_ui_cache.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/plugin/plugin_repo_service.dart';
import 'package:teampilot/services/install/install_job_registry.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/provider_usage/managed_provider_secret_store.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_adapter.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_coordinator.dart';
import 'package:teampilot/services/provider_usage/managed_provider_usage_registry.dart';
import 'package:teampilot/services/run/workspace_run_platform_factory.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/workspace/repo_clone_service.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';
import 'package:teampilot/services/terminal/workspace_shell_connector.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';
import 'package:teampilot/services/workspace/workspace_run_registry.dart';
import 'package:teampilot/services/workspace/workspace_session_groups_registry.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope_registry.dart';
import 'package:teampilot/services/workspace/workspace_worktree_registry.dart';

import 'in_memory_filesystem.dart';
import 'post_frame_test_harness.dart';
import 'test_git_command_runner.dart';
import 'test_home_target_controller.dart';
import 'package:teampilot/services/storage/home_storage.dart';

String desktopHarnessExecutable() => 'flashskyai';

/// Offline source returning only the built-in experts so roster slots
/// (`teampilot/builtin/*`) materialize without touching the network. Mirrors
/// production wiring where the shell always attaches a catalog to the team
/// cubit (app_shell.attachCatalog) — since b467c7e55 materialization is
/// skipped entirely without one, leaving default teams member-less.
class _BuiltinExpertSource implements ExpertHubSource {
  @override
  Future<List<DiscoverableMember>> fetchMembers({
    bool forceRefresh = false,
  }) async => builtinExpertMembers();

  @override
  Future<List<String>> categories({bool forceRefresh = false}) async =>
      const [];
}

late Directory desktopHarnessSessionRepoDir;
late SessionRepository desktopHarnessSessionRepo;
late HomeWorkspaceUiCache desktopHarnessHomeWorkspaceUiCache;

Future<void> setUpDesktopAppHarness() async {
  desktopHarnessSessionRepoDir = await Directory.systemTemp.createTemp(
    'widget_sess_repo_',
  );
  desktopHarnessSessionRepo = SessionRepository(
    rootDir: desktopHarnessSessionRepoDir.path,
    storage: fakeHomeStorage(),
  );
  desktopHarnessHomeWorkspaceUiCache = HomeWorkspaceUiCache(
    storage: fakeHomeStorage(),
  );
}

void tearDownDesktopAppHarness() {
  try {
    if (desktopHarnessSessionRepoDir.existsSync()) {
      desktopHarnessSessionRepoDir.deleteSync(recursive: true);
    }
  } on Object catch (_) {}
}

/// [TeamPilotApp] shares the process-wide [appRouter]. Widget tests that
/// navigate to settings must reset the location so later tests see `/home-v2`.
void resetAppRouterLocationForWidgetTests() {
  final location = appRouter.routerDelegate.currentConfiguration.uri.path;
  if (location != '/home-v2') {
    appRouter.go('/home-v2');
  }
}

/// Drives a few frames without [pumpAndSettle], which can time out when the
/// tree keeps scheduling work (e.g. router + split layout + terminal).
Future<void> pumpPhaseTransitions(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget buildTestApp({
  required LaunchProfileCubit teamCubit,
  required SessionPreferencesCubit sessionPreferencesCubit,
  ChatCubit? chatCubit,
  MemberPresenceCubit? memberPresenceCubit,
  LayoutCubit? layoutCubit,
  LlmConfigCubit? llmConfigCubit,
  AppProviderCubit? appProviderCubit,
  AppSettingsRepository? appSettings,
  AiFeatureSettingsCubit? aiFeatureSettingsCubit,
  ExtensionCubit? extensionCubit,
}) {
  final connectionModeService = ConnectionModeService(
    defaultTargetResolver: RuntimeTarget.local,
    hasSshProfiles: () => true,
  );
  final settings =
      appSettings ??
      InMemoryAppSettingsRepository(hasCompletedOnboarding: true);
  final aiFeatures =
      aiFeatureSettingsCubit ?? AiFeatureSettingsCubit(repository: settings);
  final chat =
      chatCubit ??
      ChatCubit(
        executableResolver: desktopHarnessExecutable,
        automationRepository: testAutomationRepository(),
        storage: fakeHomeStorage(),
      );
  final workbenchCubit = WorkbenchCubit();
  // Hoisted so the workbench editor opener below can share the same instances.
  final editorCubit = EditorCubit(
    storage: fakeHomeStorage(),
    fs: LocalFilesystem(),
  );
  final floatingWorkspaceCubit = FloatingWorkspaceCubit();
  final workbenchEditorOpener = WorkbenchEditorOpener(
    editor: editorCubit,
    workbench: workbenchCubit,
    floating: floatingWorkspaceCubit,
    markdownViewModes: MarkdownViewModeStore(),
    readMarkdownOpenMode: () => MarkdownOpenMode.preview,
  );
  // Mirror the production bridge wiring (app_shell.dart) so session opens feed
  // the bar and bar-close tears down the domain in harness-driven tests too.
  final chatBridge = WorkbenchChatBridge(workbench: workbenchCubit, chat: chat);
  workbenchCubit.port = chatBridge;
  chat.workbenchPort = chatBridge;
  chat.onSessionTabOpened = chatBridge.onSessionTabOpened;
  final presence =
      memberPresenceCubit ?? MemberPresenceCubit(storage: fakeHomeStorage());
  chat.bindPresenceCubit(presence);
  final managedProviderFs = InMemoryFilesystem();
  final managedUsageRepository = ManagedProviderUsageRepository(
    storage: fakeHomeStorage(filesystem: managedProviderFs),
    fs: managedProviderFs,
    cachePath: '/tp/managed-provider-usage.json',
  );
  final managedProviderRepository = ManagedProviderRepository(
    storage: fakeHomeStorage(filesystem: managedProviderFs),
    fs: managedProviderFs,
    configPath: '/tp/managed-providers.json',
    onProvidersDeleted: managedUsageRepository.deleteMany,
  );
  final managedProviderCubit = ManagedProviderCubit(
    repository: managedProviderRepository,
  );
  final managedProviderUsageCubit = ManagedProviderUsageCubit(
    coordinator: ManagedProviderUsageCoordinator(
      providerRepository: managedProviderRepository,
      usageRepository: managedUsageRepository,
      registry: ManagedProviderUsageRegistry(),
      credentials: _HarnessProviderCredentials(),
      http: _HarnessProviderHttp(),
    ),
  );
  // SessionChatView binds a History seat through the pod's HistoryStore when
  // pods own one; the pre-pod fallback reads AiHistoryCubit from context. The
  // harness must provide it or chat-workspace smoke tests throw during the
  // first build (ProviderNotFoundException) and cascade into framework teardown
  // assertions that poison the whole suite.
  final aiHistoryCubit = AiHistoryCubit(
    loader: AiHistoryLoader(
      resolveWorkContext: (launchCtx, {String? memberId}) async {
        final basePath = testHomeStorage.paths.basePath;
        return RuntimeContext(
          target: RuntimeTarget.local(),
          filesystem: LocalFilesystem(
            pathContext: AppPaths.pathContextForDataRoot(basePath),
          ),
          home: basePath,
          cwd: basePath,
          appDataRoot: basePath,
          paths: AppPaths(basePath),
        );
      },
    ),
  );
  final sshEvents = SshConnectionEvents();
  final sshCredentialStore = InMemorySshCredentialStore();
  final sshKnownHosts = InMemorySshKnownHostRepository();
  final sshClientFactory = SshClientFactory(
    credentialStore: sshCredentialStore,
    knownHostRepository: sshKnownHosts,
    events: sshEvents,
  );
  final sshCoordinator = SshProfileConnectionCoordinator(
    factory: sshClientFactory,
    events: sshEvents,
    profileResolver: (_) => null,
  );
  final extensionRepo = ExtensionRepository(
    fs: InMemoryFilesystem(),
    stateFilePath: '/test/extensions/state.json',
    manifests: builtInExtensionManifests(),
  );
  final workspaceRunRegistry = WorkspaceRunRegistry(
    storage: fakeHomeStorage(),
    platformFactory: WorkspaceRunPlatformFactory(
      storage: fakeHomeStorage(),
      extensionRepository: extensionRepo,
      projectConfigRepository: WorkspaceProjectConfigRepository(
        storage: fakeHomeStorage(filesystem: InMemoryFilesystem()),
      ),
      fs: InMemoryFilesystem(),
      detector: ExtensionDetector(
        processRunner: (e, a, {environment}) async =>
            ProcessResult(0, 1, '', ''),
      ),
    ),
  );
  final notificationCubit = NotificationCubit(storage: fakeHomeStorage());
  final progressActivityCubit = ProgressActivityCubit(
    historyRecorder: notificationCubit,
  );
  final installJobRegistry = InstallJobRegistry(
    progressCubit: progressActivityCubit,
  );

  return MultiRepositoryProvider(
    providers: [
      RepositoryProvider<HomeStorage>.value(value: testHomeStorage),
      RepositoryProvider<AppSettingsRepository>.value(value: settings),
      RepositoryProvider<SessionRepository>.value(
        value: desktopHarnessSessionRepo,
      ),
      RepositoryProvider<HomeWorkspaceUiCache>.value(
        value: desktopHarnessHomeWorkspaceUiCache,
      ),
      RepositoryProvider<ConnectionModeService>.value(
        value: connectionModeService,
      ),
      RepositoryProvider<HomeTargetController>.value(
        value: testHomeTargetController(),
      ),
      RepositoryProvider<GitCommandRunner>.value(
        value: const TestGitCommandRunner(),
      ),
      RepositoryProvider<WorkspaceTerminalRegistry>(
        create: (_) => WorkspaceTerminalRegistry(),
      ),
      RepositoryProvider<WorkspaceShellConnector>(
        create: (_) => WorkspaceShellConnector(
          transportFactory: TerminalTransportFactory(
            sshProfileRepository: SshProfileRepository(
              storage: fakeHomeStorage(),
            ),
            sshCredentialStore: sshCredentialStore,
            sshKnownHostRepository: sshKnownHosts,
          ),
          sshProfileRepository: SshProfileRepository(
            storage: fakeHomeStorage(),
          ),
        ),
      ),
      RepositoryProvider<SshProfileRepository>(
        create: (_) => SshProfileRepository(storage: fakeHomeStorage()),
      ),
      RepositoryProvider<SshProfileConnectionCoordinator>.value(
        value: sshCoordinator,
      ),
      RepositoryProvider<GitRepoStore>(create: (_) => GitRepoStore()),
      RepositoryProvider<WorkspaceFileTreeStore>(
        create: (_) => WorkspaceFileTreeStore(),
      ),
      RepositoryProvider<WorkspaceWorktreeRegistry>(
        create: (_) => WorkspaceWorktreeRegistry(storage: testHomeStorage),
      ),
      RepositoryProvider<WorkspaceToolsScopeRegistry>(
        create: (_) => WorkspaceToolsScopeRegistry(),
      ),
      RepositoryProvider<WorkspaceSessionGroupsRegistry>(
        create: (_) =>
            WorkspaceSessionGroupsRegistry(storage: fakeHomeStorage()),
      ),
      RepositoryProvider<CommandBus>(create: (_) => CommandBus()),
      RepositoryProvider<WorkspaceChromeCommands>(
        create: (_) => WorkspaceChromeCommands(),
      ),
      RepositoryProvider<UiZoomBaseline>(create: (_) => UiZoomBaseline()),
      RepositoryProvider<WorkspaceRunRegistry>.value(
        value: workspaceRunRegistry,
      ),
      RepositoryProvider<RunCommandHost>(create: (_) => RunCommandHost()),
      RepositoryProvider<WorkspaceSearchHost>(
        create: (_) => WorkspaceSearchHost(),
      ),
      RepositoryProvider<WorkspaceContentSearchHost>(
        create: (_) => WorkspaceContentSearchHost(),
      ),
      RepositoryProvider<WorkspaceSearchIndexes>(
        create: (_) => WorkspaceSearchIndexes(storage: fakeHomeStorage()),
      ),
      RepositoryProvider<WorkbenchEditorOpener>.value(
        value: workbenchEditorOpener,
      ),
      RepositoryProvider<InstallJobRegistry>.value(value: installJobRegistry),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) {
            final bootstrap = AppBootstrapCubit();
            bootstrap.markAppReady(showOnboardingWizard: false);
            return bootstrap;
          },
        ),
        BlocProvider.value(value: teamCubit),
        BlocProvider.value(value: chat),
        BlocProvider.value(value: presence),
        BlocProvider(create: (_) => AgentAttentionCubit(pruneInterval: null)),
        BlocProvider(create: (_) => ConfigCubit()),
        BlocProvider.value(value: llmConfigCubit ?? testLlmConfigCubit()),
        BlocProvider.value(value: appProviderCubit!),
        BlocProvider.value(value: managedProviderCubit),
        BlocProvider.value(value: managedProviderUsageCubit),
        BlocProvider.value(value: layoutCubit ?? LayoutCubit()),
        BlocProvider.value(value: sessionPreferencesCubit),
        BlocProvider.value(value: aiFeatures),
        BlocProvider.value(value: aiHistoryCubit),
        BlocProvider(create: (_) => ShortcutCubit(storage: fakeHomeStorage())),
        BlocProvider.value(value: editorCubit),
        BlocProvider.value(value: workbenchCubit),
        BlocProvider.value(
          value:
              extensionCubit ??
              ExtensionCubit(
                extensionRepo,
                ExtensionAcquisitionEngine(
                  runner: (c) async =>
                      const CliInstallerCommandResult(exitCode: 0),
                ),
                detector: ExtensionDetector(
                  processRunner: (e, a, {environment}) async =>
                      ProcessResult(0, 1, '', ''),
                ),
              ),
        ),
        BlocProvider(
          create: (_) => CliPresetsCubit(
            repository: CliPresetsRepository(
              fs: InMemoryFilesystem(),
              presetsPath: '/cli-presets.json',
            ),
          ),
        ),
        BlocProvider(create: (_) => testSkillCubit()),
        BlocProvider(
          create: (_) {
            final repo = PluginRepository(storage: fakeHomeStorage());
            return PluginCubit(
              repository: repo,
              installService: repo.install,
              repoService: PluginRepoService(storage: fakeHomeStorage()),
              storage: fakeHomeStorage(),
            );
          },
        ),
        BlocProvider(create: (_) => WorkspaceToolsCubit()),
        BlocProvider.value(value: notificationCubit),
        BlocProvider.value(value: progressActivityCubit),
        // HomeShell listens to RepoCloneCubit; provide one over a fake gateway
        // so no real `git` process can ever spawn from harness-driven tests.
        BlocProvider(
          create: (_) => RepoCloneCubit(
            progressActivityCubit: progressActivityCubit,
            service: _HarnessRepoCloneGateway(),
          ),
        ),
        BlocProvider.value(value: floatingWorkspaceCubit),
        BlocProvider(
          create: (_) => SshConnectionCubit(
            factory: sshClientFactory,
            coordinator: sshCoordinator,
          ),
        ),
        BlocProvider(
          create: (_) =>
              testAutomationCubit(sessionRepository: desktopHarnessSessionRepo),
        ),
      ],
      child: CliToolRegistryScope(
        registry: CliToolRegistry.builtIn(),
        child: const TeamPilotApp(),
      ),
    ),
  );
}

Future<void> pumpDesktopApp(
  WidgetTester tester,
  LaunchProfileCubit teamCubit, {
  ChatCubit? chatCubit,
  LayoutCubit? layoutCubit,
  LlmConfigCubit? llmConfigCubit,
  AppProviderCubit? appProviderCubit,
  SessionPreferencesCubit? sessionPreferencesCubit,
}) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final sessionCubit =
      sessionPreferencesCubit ??
      (await tester.runAsync(testSessionPreferencesCubit))!;
  final providerCubit =
      appProviderCubit ??
      (await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('providers_widget_');
        return AppProviderCubit(
          storage: fakeHomeStorage(),
          repository: AppProviderRepository(
            basePath: dir.path,
            storage: fakeHomeStorage(),
          ),
        );
      }))!;
  await tester.pumpWidget(
    buildTestApp(
      teamCubit: teamCubit,
      sessionPreferencesCubit: sessionCubit,
      chatCubit: chatCubit,
      layoutCubit: layoutCubit,
      llmConfigCubit: llmConfigCubit,
      appProviderCubit: providerCubit,
    ),
  );
  // Avoid pumpAndSettle: router + split-view can schedule frames indefinitely in tests.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

LlmConfigCubit testLlmConfigCubit({
  LlmConfig initialConfig = const LlmConfig(),
}) {
  return LlmConfigCubit(
    appSettings: InMemoryAppSettingsRepository(),
    storage: fakeHomeStorage(),
    initialConfig: initialConfig,
  );
}

Future<SessionPreferencesCubit> testSessionPreferencesCubit() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return SessionPreferencesCubit(
    repository: SessionPreferencesRepository(prefs),
  );
}

Future<LaunchProfileCubit> createTeamCubit({TeamLauncher? launcher}) async {
  final tmp = await Directory.systemTemp.createTemp('teams_widget_');
  final appData = await Directory.systemTemp.createTemp('teams_widget_app_');
  final repository = testLaunchProfileRepository(tmp);
  final cubit = LaunchProfileCubit(
    repository: repository,
    sessionRepository: SessionRepository(storage: fakeHomeStorage()),
    storage: fakeHomeStorage(),
    executableResolver: desktopHarnessExecutable,
    launcher: launcher ?? (_, __) async {},
    appDataBasePath: appData.path,
    configProfileService: ConfigProfileService(
      basePath: appData.path,
      storage: fakeHomeStorage(),
    ),
  )..attachCatalog(ExpertHubCatalog(source: _BuiltinExpertSource()));
  await cubit.load();
  return cubit;
}

/// No-op [RepoCloneGateway]: cancels immediately without spawning anything.
class _HarnessRepoCloneGateway implements RepoCloneGateway {
  @override
  Future<RepoCloneResult> clone(
    RepoCloneRequest request, {
    required void Function(RepoCloneProgress progress) onProgress,
    required bool Function() isCancelled,
  }) async {
    return RepoCloneResult(
      outcome: RepoCloneOutcome.cancelled,
      destPath: request.parentDir,
    );
  }
}

class _HarnessProviderCredentials implements ProviderCredentialResolver {
  @override
  Future<ProviderCredentialScope> resolve(ManagedProvider provider) async =>
      ManagedProviderCredentialScope(const {});
}

class _HarnessProviderHttp implements ProviderUsageHttpClient {
  @override
  Future<ProviderUsageHttpResponse> send(ProviderUsageHttpRequest request) {
    return Future.error(StateError('HTTP unused in desktop app harness'));
  }
}

/// [testWidgets] uses a fake-async zone; futures from real disk I/O (temp dirs,
/// team JSON) must be created inside [WidgetTester.runAsync] or they never complete.
Future<LaunchProfileCubit> createTeamCubitInTest(
  WidgetTester tester, {
  TeamLauncher? launcher,
}) async {
  final cubit = await tester.runAsync(
    () => createTeamCubit(launcher: launcher),
  );
  expect(cubit, isNotNull);
  return cubit!;
}
