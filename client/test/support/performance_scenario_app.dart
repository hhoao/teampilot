import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/app_bootstrap_cubit.dart';
import 'package:teampilot/cubits/ai_feature_settings_cubit.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/board_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/mailbox_cubit.dart';
import 'package:teampilot/cubits/mcp_cubit.dart';
import 'package:teampilot/cubits/app_update_cubit.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/repositories/mcp_repository.dart';
import 'package:teampilot/cubits/config_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/extension_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/llm_config_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/cubits/notification_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/workspace_tools_cubit.dart';
import 'package:teampilot/main.dart';
import 'package:teampilot/models/llm_config.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/extension_repository.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/router/app_router.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/extension/builtin_manifests.dart';
import 'package:teampilot/services/extension/extension_acquisition_engine.dart';
import 'package:teampilot/services/extension/extension_detector.dart';
import 'package:teampilot/services/git/git_command_runner.dart';
import 'package:teampilot/services/git/git_repo_store.dart';
import 'package:teampilot/services/file_tree/workspace_file_tree_store.dart';
import 'package:teampilot/services/home_workspace/home_workspace_ui_cache.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';
import 'package:teampilot/services/terminal/workspace_shell_connector.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope_registry.dart';
import 'package:teampilot/services/workspace/workspace_worktree_registry.dart';

import '../support/in_memory_filesystem.dart';
import '../support/test_git_command_runner.dart';
import '../support/test_home_target_controller.dart';

const performanceTestExecutable = 'flashskyai';

class PerformanceScenarioApp {
  PerformanceScenarioApp({
    required this.sessionRepository,
    required this.homeWorkspaceUiCache,
  });

  final SessionRepository sessionRepository;
  final HomeWorkspaceUiCache homeWorkspaceUiCache;

  static Future<PerformanceScenarioApp> create() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final repoDir = await Directory.systemTemp.createTemp('perf_sess_repo_');
    final cache = HomeWorkspaceUiCache();
    return PerformanceScenarioApp(
      sessionRepository: SessionRepository(rootDir: repoDir.path),
      homeWorkspaceUiCache: cache,
    );
  }

  Future<void> warmCaches() => homeWorkspaceUiCache.warm();

  Widget build({
    required LaunchProfileCubit teamCubit,
    required SessionPreferencesCubit sessionPreferencesCubit,
    ChatCubit? chatCubit,
    LayoutCubit? layoutCubit,
  }) {
    final settings = InMemoryAppSettingsRepository(
      hasCompletedOnboarding: true,
    );
    final chat =
        chatCubit ?? ChatCubit(executableResolver: () => performanceTestExecutable);
    final presence = MemberPresenceCubit();
    chat.bindPresenceCubit(presence);

    return BlocProvider(
      create: (_) => AppBootstrapCubit(),
      child: MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppSettingsRepository>.value(value: settings),
        RepositoryProvider<SessionRepository>.value(value: sessionRepository),
        RepositoryProvider<HomeWorkspaceUiCache>.value(
          value: homeWorkspaceUiCache,
        ),
        RepositoryProvider<ConnectionModeService>.value(
          value: ConnectionModeService(
            defaultTargetResolver: RuntimeTarget.local,
            hasSshProfiles: () => true,
          ),
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
              sshProfileRepository: SshProfileRepository(),
              sshCredentialStore: InMemorySshCredentialStore(),
              sshKnownHostRepository: InMemorySshKnownHostRepository(),
            ),
            sshProfileRepository: SshProfileRepository(),
          ),
        ),
        RepositoryProvider<GitRepoStore>(create: (_) => GitRepoStore()),
        RepositoryProvider<WorkspaceFileTreeStore>(
          create: (_) => WorkspaceFileTreeStore(),
        ),
        RepositoryProvider<WorkspaceWorktreeRegistry>(
          create: (_) => WorkspaceWorktreeRegistry(),
        ),
        RepositoryProvider<WorkspaceToolsScopeRegistry>(
          create: (_) => WorkspaceToolsScopeRegistry(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: teamCubit),
          BlocProvider.value(value: chat),
          BlocProvider.value(value: presence),
          BlocProvider(create: (_) => ConfigCubit()),
          BlocProvider(
            create: (_) => LlmConfigCubit(
              appSettings: InMemoryAppSettingsRepository(),
              initialConfig: const LlmConfig(),
            ),
          ),
          BlocProvider(
            create: (_) => AppProviderCubit(
              repository: AppProviderRepository(
                basePath: Directory.systemTemp.path,
              ),
            ),
          ),
          BlocProvider.value(value: layoutCubit ?? LayoutCubit()),
          BlocProvider.value(value: sessionPreferencesCubit),
          BlocProvider(
            create: (_) => AiFeatureSettingsCubit(repository: settings),
          ),
          BlocProvider(create: (_) => EditorCubit(fs: LocalFilesystem())),
          BlocProvider(
            create: (_) => ExtensionCubit(
              ExtensionRepository(
                fs: InMemoryFilesystem(),
                stateFilePath: '/test/extensions/state.json',
                manifests: builtInExtensionManifests(),
              ),
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
          BlocProvider(create: (_) => WorkspaceToolsCubit()),
          BlocProvider(create: (_) => NotificationCubit()),
          BlocProvider(
            create: (_) => CliPresetsCubit(
              repository: CliPresetsRepository(
                fs: InMemoryFilesystem(),
                presetsPath: '/test/cli-presets.json',
              ),
            ),
          ),
          BlocProvider(
            create: (_) => MailboxCubit(
              activeBus: () => chat.activeTab?.teamBus,
            ),
          ),
          BlocProvider(
            create: (_) => BoardCubit(
              activeBus: () => chat.activeTab?.teamBus,
            ),
          ),
          BlocProvider(create: (_) => McpCubit(McpRepository())),
          BlocProvider(
            create: (_) => AppUpdateCubit(settings: settings),
          ),
          BlocProvider(
            create: (_) => SshProfileCubit(
              profileRepository: SshProfileRepository(),
              credentialStore: InMemorySshCredentialStore(),
            ),
          ),
        ],
        child: CliToolRegistryScope(
          registry: CliToolRegistry.builtIn(),
          child: const TeamPilotApp(),
        ),
      ),
    ),
    );
  }
}

class PerformanceFakeTerminalSession extends TerminalSession {
  PerformanceFakeTerminalSession({
    super.executable = performanceTestExecutable,
    super.scrollbackLines = 10000,
  });
}

Future<LaunchProfileCubit> createPerformanceTeamCubit(
  WidgetTester tester,
) async {
  final tmp = await tester.runAsync(
    () => Directory.systemTemp.createTemp('perf_teams_'),
  );
  final appData = await tester.runAsync(
    () => Directory.systemTemp.createTemp('perf_teams_app_'),
  );
  expect(tmp, isNotNull);
  expect(appData, isNotNull);
  final repository = LaunchProfileRepository(rootDir: tmp!.path);
  final cubit = LaunchProfileCubit(
    repository: repository,
    sessionRepository: SessionRepository(),
    executableResolver: () => performanceTestExecutable,
    launcher: (_, __) async {},
    appDataBasePath: appData!.path,
  );
  await tester.runAsync(cubit.load);
  return cubit;
}

Future<SessionPreferencesCubit> createPerformanceSessionPreferences(
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await tester.runAsync(SharedPreferences.getInstance);
  expect(prefs, isNotNull);
  return SessionPreferencesCubit(
    repository: SessionPreferencesRepository(prefs!),
  );
}

Future<void> pumpPerformanceDesktopApp(
  WidgetTester tester,
  PerformanceScenarioApp scenario, {
  required LaunchProfileCubit teamCubit,
  required SessionPreferencesCubit sessionPreferencesCubit,
  ChatCubit? chatCubit,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    scenario.build(
      teamCubit: teamCubit,
      sessionPreferencesCubit: sessionPreferencesCubit,
      chatCubit: chatCubit,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> pumpPerformanceFrames(
  WidgetTester tester, {
  int count = 12,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(step);
  }
}

void resetPerformanceRouterHome() {
  final location = appRouter.routerDelegate.currentConfiguration.uri.path;
  if (location != '/home-v2') {
    appRouter.go('/home-v2');
  }
}
