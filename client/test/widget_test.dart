import 'dart:io';

import 'package:google_fonts/google_fonts.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/cubits/app_bootstrap_cubit.dart';
import 'package:teampilot/cubits/ai_feature_settings_cubit.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/notification_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/cubits/config_cubit.dart';
import 'package:teampilot/cubits/extension_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/workspace_tools_cubit.dart';
import 'package:teampilot/services/terminal/workspace_shell_connector.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';
import 'package:teampilot/services/git/git_repo_store.dart';
import 'package:teampilot/services/file_tree/workspace_file_tree_store.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope_registry.dart';
import 'package:teampilot/services/workspace/workspace_worktree_registry.dart';
import 'package:teampilot/cubits/llm_config_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/main.dart';
import 'package:teampilot/models/llm_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/personal_profile.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/layout_repository.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/extension_repository.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/services/extension/builtin_manifests.dart';
import 'package:teampilot/services/extension/extension_acquisition_engine.dart';
import 'package:teampilot/services/extension/extension_detector.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/cli/registry/config_profile/claude_config_profile_capability.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/git/git_command_runner.dart';
import 'package:teampilot/services/home_workspace/home_workspace_ui_cache.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'support/test_runtime_context.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';
import 'package:teampilot/services/team_bus/bus_user_line_capture.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/router/app_router.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/utils/app_keys.dart';
import 'package:teampilot/utils/team_member_naming.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_memory_filesystem.dart';
import 'support/post_frame_test_harness.dart';
import 'support/test_git_command_runner.dart';
import 'support/test_home_target_controller.dart';

ExtensionCubit _testExtensionCubit() => ExtensionCubit(
  ExtensionRepository(
    fs: InMemoryFilesystem(),
    stateFilePath: '/test/extensions/state.json',
    manifests: builtInExtensionManifests(),
  ),
  ExtensionAcquisitionEngine(
    runner: (c) async => const CliInstallerCommandResult(exitCode: 0),
  ),
  detector: ExtensionDetector(
    processRunner: (e, a, {environment}) async => ProcessResult(0, 1, '', ''),
  ),
);

String _testExecutable() => 'flashskyai';

Future<void> _deleteTempDirBestEffort(Directory dir) =>
    deleteTempDirBestEffort(dir);

Future<void> _tearDownChatCubitWithSessionPersist(
  ChatCubit cubit,
  PostFrameTestHarness postFrame,
) async {
  await postFrame.flush();
  await drainPendingAsyncWork(rounds: 15);
  if (!cubit.isClosed) {
    await cubit.close();
  }
  await drainPendingAsyncWork(rounds: 15);
}

late Directory _widgetTestSessionRepoDir;
late SessionRepository _widgetTestSessionRepo;
late HomeWorkspaceUiCache _widgetTestHomeWorkspaceUiCache;

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
  final chat = chatCubit ?? ChatCubit(executableResolver: _testExecutable);
  final presence = memberPresenceCubit ?? MemberPresenceCubit();
  chat.bindPresenceCubit(presence);

  return MultiRepositoryProvider(
    providers: [
      RepositoryProvider<AppSettingsRepository>.value(value: settings),
      RepositoryProvider<SessionRepository>.value(
        value: _widgetTestSessionRepo,
      ),
      RepositoryProvider<HomeWorkspaceUiCache>.value(
        value: _widgetTestHomeWorkspaceUiCache,
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
        BlocProvider(create: (_) => ConfigCubit()),
        BlocProvider.value(value: llmConfigCubit ?? testLlmConfigCubit()),
        BlocProvider.value(value: appProviderCubit!),
        BlocProvider.value(value: layoutCubit ?? LayoutCubit()),
        BlocProvider.value(value: sessionPreferencesCubit),
        BlocProvider.value(value: aiFeatures),
        BlocProvider(create: (_) => EditorCubit(fs: LocalFilesystem())),
        BlocProvider.value(value: extensionCubit ?? _testExtensionCubit()),
        BlocProvider(create: (_) => WorkspaceToolsCubit()),
        BlocProvider(create: (_) => NotificationCubit()),
      ],
      child: CliToolRegistryScope(
        registry: CliToolRegistry.builtIn(),
        child: const TeamPilotApp(),
      ),
    ),
  );
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

Future<void> pumpDesktopApp(
  WidgetTester tester,
  LaunchProfileCubit teamCubit, {
  ChatCubit? chatCubit,
  LayoutCubit? layoutCubit,
  LlmConfigCubit? llmConfigCubit,
  AppProviderCubit? appProviderCubit,
  SessionPreferencesCubit? sessionPreferencesCubit,
}) async {
  tester.view.physicalSize = const Size(1200, 700);
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
          repository: AppProviderRepository(basePath: dir.path),
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
    sessionRepository: SessionRepository(),
    executableResolver: _testExecutable,
    launcher: launcher ?? (_, __) async {},
    appDataBasePath: appData.path,
    configProfileService: ConfigProfileService(basePath: appData.path),
  );
  await cubit.load();
  return cubit;
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

class FakeTerminalSession extends TerminalSession {
  FakeTerminalSession({
    super.executable = 'flashskyai',
    super.scrollbackLines = 10000,
  });

  var _running = false;
  final connectedMembers = <String>[];
  final resumedSessions = <String>[];
  final lastFixedSessionIds = <String?>[];
  final lastResumeSessionIds = <String?>[];
  final lastAdditionalDirectoriesLists = <List<String>>[];
  final lastExtraEnvironments = <Map<String, String>?>[];

  @override
  bool get isRunning => _running;

  @override
  void connect({
    required String workingDirectory,
    List<String> additionalDirectories = const [],
    String? fixedSessionId,
    String? resumeSessionId,
    ShellLaunchSpec? shellLaunch,
    Map<String, String>? extraEnvironment,
    void Function()? onProcessStarted,
    void Function(String message)? onProcessFailed,
    void Function()? onProcessExited,
    void Function(String line)? onFirstUserLineSubmitted,
    void Function(String line)? onEveryUserLineSubmitted,
    BusUserInputRouting? busUserInputRouting,
    String? executableOverride,
  }) {
    lastFixedSessionIds.add(fixedSessionId);
    lastResumeSessionIds.add(resumeSessionId);
    lastAdditionalDirectoriesLists.add(
      List<String>.from(
        shellLaunch?.launchContext.additionalDirectories ??
            additionalDirectories,
      ),
    );
    lastExtraEnvironments.add(
      extraEnvironment == null
          ? null
          : Map<String, String>.from(extraEnvironment),
    );
    _running = true;
    if (resumeSessionId != null && resumeSessionId.isNotEmpty) {
      resumedSessions.add(resumeSessionId);
    }
    final member = shellLaunch?.launchContext.member;
    if (member != null) {
      connectedMembers.add(member.id);
    }
    onProcessStarted?.call();
  }

  @override
  void disconnect() {
    _running = false;
  }

  @override
  void dispose() {
    _running = false;
  }
}

class _FixedResumeLifecycleService extends SessionLifecycleService {
  _FixedResumeLifecycleService({required this.resume})
    : super(appDataBasePath: Directory.systemTemp.path);

  final bool resume;

  @override
  Future<ShellLaunchSpec> prepareShellLaunch({
    required AppSession session,
    TeamProfile? team,
    TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    Workspace? workspace,
    PersonalProfile? personal,
    String? profileId,
    String? llmConfigPathOverride,
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
  }) async {
    final spec = await super.prepareShellLaunch(
      session: session,
      team: team,
      member: member,
      memberBinding: memberBinding,
      workspace: workspace,
      personal: personal,
      llmConfigPathOverride: llmConfigPathOverride,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
    );
    return _withFixedResume(spec);
  }

  @override
  Future<ShellLaunchSpec> prepareTeamShellLaunchFromEnvironment({
    required AppSession session,
    required TeamProfile team,
    required TeamMemberConfig member,
    SessionMemberBinding? memberBinding,
    Workspace? workspace,
    required Map<String, String> environment,
    List<String> launchWarnings = const [],
  }) async {
    final spec = await super.prepareTeamShellLaunchFromEnvironment(
      session: session,
      team: team,
      member: member,
      memberBinding: memberBinding,
      workspace: workspace,
      environment: environment,
      launchWarnings: launchWarnings,
    );
    return _withFixedResume(spec);
  }

  ShellLaunchSpec _withFixedResume(ShellLaunchSpec spec) {
    final plan = spec.plan;
    return ShellLaunchSpec(
      plan: LaunchPlan(
        env: plan.env,
        resume: resume,
        taskId: plan.taskId,
        createSessionId: resume ? null : plan.taskId,
        resumeSessionId: resume ? plan.taskId : null,
        cliTeamName: plan.cliTeamName,
        memberConfigDir: plan.memberConfigDir,
        resolvedRoots: plan.resolvedRoots,
        warnings: plan.warnings,
      ),
      launchContext: spec.launchContext,
      sessionTeam: spec.sessionTeam,
    );
  }
}

class TestChatCubit extends ChatCubit {
  TestChatCubit._(
    this.postFrame, {
    super.sessionRepository,
    SessionLifecycleService? lifecycleService,
  }) : super(
         executableResolver: _testExecutable,
         terminalSessionFactory:
             ({required String executable, int scrollbackLines = 10000}) =>
                 FakeTerminalSession(
                   executable: executable,
                   scrollbackLines: scrollbackLines,
                 ),
         postFrameScheduler: postFrame.scheduler,
         lifecycleService:
             lifecycleService ?? _FixedResumeLifecycleService(resume: false),
       );

  factory TestChatCubit() {
    final harness = PostFrameTestHarness();
    return TestChatCubit._(harness, sessionRepository: _widgetTestSessionRepo);
  }

  final PostFrameTestHarness postFrame;

  void seedChatData({
    List<Workspace> workspaces = const [],
    List<AppSession> sessions = const [],
  }) {
    ingestWorkspaceSessionSnapshot(workspaces: workspaces, sessions: sessions);
  }
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(() async {
    _widgetTestSessionRepoDir = await Directory.systemTemp.createTemp(
      'widget_sess_repo_',
    );
    _widgetTestSessionRepo = SessionRepository(
      rootDir: _widgetTestSessionRepoDir.path,
    );
    _widgetTestHomeWorkspaceUiCache = HomeWorkspaceUiCache();
  });
  tearDownAll(() {
    try {
      if (_widgetTestSessionRepoDir.existsSync()) {
        _widgetTestSessionRepoDir.deleteSync(recursive: true);
      }
    } on Object catch (_) {}
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    setUpTestAppStorage();
    resetAppRouterLocationForWidgetTests();
  });

  tearDown(() {
    tearDownTestAppStorage();
    resetAppRouterLocationForWidgetTests();
  });

  testWidgets('renders chat workbench shell on workspace route', (
    tester,
  ) async {
    final teamCubit = await createTeamCubitInTest(tester);
    final postFrame = PostFrameTestHarness();
    final chatCubit = ChatCubit(
      executableResolver: _testExecutable,
      terminalSessionFactory:
          ({required String executable, int scrollbackLines = 10000}) =>
              FakeTerminalSession(
                executable: executable,
                scrollbackLines: scrollbackLines,
              ),
      postFrameScheduler: postFrame.scheduler,
      sessionRepository: _widgetTestSessionRepo,
    );
    late final Workspace workspace;
    await tester.runAsync(() async {
      workspace = await _widgetTestSessionRepo.createWorkspace([WorkspaceFolder(path: '/work/current')]);
      chatCubit.ingestWorkspaceSessionSnapshot(
        workspaces: [workspace],
        sessions: const [],
      );
    });
    await pumpDesktopApp(tester, teamCubit, chatCubit: chatCubit);
    final teamId = teamCubit.state.selectedTeam!.id;
    appRouter.go('/home-v2/workspace/${workspace.workspaceId}?as=$teamId');
    await tester.pump();
    await pumpPhaseTransitions(tester);

    expect(find.byKey(AppKeys.chatWorkspace), findsOneWidget);
    expect(find.byKey(AppKeys.rightToolsPanel), findsOneWidget);
    expect(find.byKey(AppKeys.membersPanel), findsOneWidget);
    // Lazy TabbedPanel mounts only the selected tool tab; file tree is off-tab.
    expect(find.byKey(AppKeys.fileTreePanel), findsNothing);
    expect(find.text('team-lead'), findsWidgets);
    expect(chatCubit.state.tabs.length, 0);
    final workbenchCtx = tester.element(find.byKey(AppKeys.chatWorkspace));
    final l10n = AppLocalizations.of(workbenchCtx);
    expect(find.text(l10n.sessionReadyTitle), findsOneWidget);
    expect(find.text(l10n.sessionReadySubtitle('team-lead')), findsOneWidget);

    final selectedTeam = teamCubit.state.selectedTeam;
    expect(selectedTeam, isNotNull);
    chatCubit.setActiveWorkspace(workspace.workspaceId);
    // Real repository I/O must run inside runAsync in widget tests.
    await tester.runAsync(() async {
      await chatCubit.connectWorkspaceSession(
        TeamSessionConnect(selectedTeam!),
      );
    });
    await tester.pump();
    await tester.runAsync(() async {
      await drainPendingAsyncWork();
      await postFrame.flush();
    });
    await tester.pump();
    expect(chatCubit.state.tabs.length, 1);
    expect(chatCubit.state.tabs.single.id.startsWith('local-'), isFalse);
    expect(chatCubit.isMemberRunning('team-lead'), isTrue);
  });

  testWidgets('renders settings shell with title bar and icon navigation', (
    tester,
  ) async {
    final teamCubit = await createTeamCubitInTest(tester);
    await pumpDesktopApp(tester, teamCubit);

    appRouter.go('/config');
    await pumpPhaseTransitions(tester);

    expect(
      find.text('Manage FlashskyAI team and model settings.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.dashboard_customize_outlined), findsWidgets);
    expect(find.byIcon(Icons.memory_outlined), findsNothing);
  });

  testWidgets('settings pages use the global component theme', (tester) async {
    final teamCubit = await createTeamCubitInTest(tester);
    await pumpDesktopApp(tester, teamCubit);

    appRouter.go('/providers/claude');
    await pumpPhaseTransitions(tester);

    final providerCtx = tester.element(find.byKey(AppKeys.llmConfigWorkspace));
    final providerTheme = Theme.of(providerCtx);
    final cs = providerTheme.colorScheme;
    expect(cs.primary, themePresetSwatchPrimary(kDefaultThemeColorPreset));

    final providerList = tester.widget<Material>(
      find.byKey(AppKeys.llmProviderList),
    );
    expect(providerList.color, cs.surfaceContainer);
  });

  testWidgets('desktop add provider opens form in detail area', (tester) async {
    final teamCubit = await createTeamCubitInTest(tester);
    await pumpDesktopApp(tester, teamCubit);

    appRouter.go('/providers/claude');
    await pumpPhaseTransitions(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(AppKeys.llmProviderList),
        matching: find.byIcon(Icons.add),
      ),
    );
    await pumpPhaseTransitions(tester);
    await tester.tap(find.text('Add Provider').last);
    await pumpPhaseTransitions(tester);

    expect(find.byKey(AppKeys.llmProviderList), findsOneWidget);
    expect(find.text('Add Provider'), findsWidgets);
    expect(find.text('Provider name'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
  });

  testWidgets('cli settings configure Claude Code CLI path', (tester) async {
    final teamCubit = await createTeamCubitInTest(tester);
    final sessionCubit = await tester.runAsync(testSessionPreferencesCubit);
    expect(sessionCubit, isNotNull);
    await sessionCubit!.load();

    await pumpDesktopApp(
      tester,
      teamCubit,
      sessionPreferencesCubit: sessionCubit,
    );

    appRouter.go('/config');
    await pumpPhaseTransitions(tester);
    await tester.tap(find.byKey(AppKeys.configCliSectionButton));
    await pumpPhaseTransitions(tester);

    expect(find.text('Claude Code CLI path'), findsOneWidget);
    final claudeField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.key == AppKeys.claudeCliExecutablePathField,
    );
    await tester.ensureVisible(claudeField);
    await tester.enterText(claudeField, '/opt/bin/claude');
    await tester.pump(const Duration(milliseconds: 500));

    expect(sessionCubit.state.preferences.cliExecutablePaths, {
      'claude': '/opt/bin/claude',
    });
  });

  test('opening a team session tab starts team-lead member shell', () async {
    final team = TeamProfile(
      id: 'default-team',
      name: 'Default Team',
      members: TeamMemberNaming.defaultRoster(),
    );
    final postFrame = PostFrameTestHarness();
    final repo = SessionRepository(
      rootDir: (await Directory.systemTemp.createTemp('sidebar_sess_')).path,
    );
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/work/current')]);
    final session = await repo.createSession(
      workspace.workspaceId,
      sessionTeam: team.id,
      rosterMembers: team.members,
    );
    final chatCubit = ChatCubit(
      executableResolver: _testExecutable,
      sessionRepository: repo,
      terminalSessionFactory:
          ({required String executable, int scrollbackLines = 10000}) =>
              FakeTerminalSession(
                executable: executable,
                scrollbackLines: scrollbackLines,
              ),
      postFrameScheduler: postFrame.scheduler,
      lifecycleService: _FixedResumeLifecycleService(resume: false),
    );
    addTearDown(chatCubit.close);
    await chatCubit.loadWorkspaceData(repo);

    await chatCubit.requestOpenSession(
        SessionOpenRequest(
          session: session, team: team,
      member: team.members.first,
      repo: repo,
        ),
      );
    await drainPendingAsyncWork();
    await postFrame.flush();

    expect(chatCubit.state.activeSessionId, session.sessionId);
    expect(chatCubit.state.selectedMemberId, 'team-lead');
    expect(chatCubit.isMemberRunning('team-lead'), isTrue);
  });

  test('terminal views keep IME text input enabled', () {
    final terminalSources = [
      File('lib/pages/chat_workbench.dart'),
      File('lib/widgets/ui_warmup.dart'),
    ];

    for (final sourceFile in terminalSources) {
      final source = sourceFile.readAsStringSync();

      expect(
        source,
        isNot(contains('hardwareKeyboardOnly: true')),
        reason: '${sourceFile.path} must use TextInput so Chinese IME works.',
      );
    }
  });

  test('team cubit manages teams', () async {
    final tmp = await Directory.systemTemp.createTemp('teams_cubit_');
    final appData = await Directory.systemTemp.createTemp('teams_cubit_app_');
    final repository = testLaunchProfileRepository(tmp);
    final cubit = LaunchProfileCubit(
      repository: repository,
      sessionRepository: SessionRepository(),
      executableResolver: _testExecutable,
      appDataBasePath: appData.path,
      configProfileService: ConfigProfileService(basePath: appData.path),
    );
    await cubit.load();

    expect(cubit.state.selectedTeam?.name, 'Default Team');
    expect(cubit.state.teams.length, 1);
    expect(cubit.state.selectedTeam?.members.length, 3);
    expect(cubit.state.selectedTeam?.members.map((m) => m.id).toList(), [
      'team-lead',
      'developer',
      'reviewer',
    ]);

    cubit.selectTeam('default-team');
    expect(cubit.state.selectedTeam?.name, 'Default Team');

    await cubit.addMember();
    expect(cubit.state.selectedTeam?.members.length, 4);
    expect(cubit.state.statusMessage, contains('Added'));
  });

  test('layout cubit persists preferences', () async {
    final cubit = LayoutCubit(
      repository: LayoutRepository(await SharedPreferences.getInstance()),
    );
    await cubit.load();

    await cubit.setThemeMode('dark');
    expect(cubit.state.preferences.themeMode, 'dark');
  });

  test('config cubit navigates sections', () {
    final cubit = ConfigCubit();
    expect(cubit.state.section, ConfigSection.layout);

    cubit.selectSection(ConfigSection.session);
    expect(cubit.state.section, ConfigSection.session);

    cubit.selectSection(ConfigSection.layout);
    expect(cubit.state.section, ConfigSection.layout);
  });

  test('chat cubit manages tabs and selection', () {
    final cubit = ChatCubit(executableResolver: _testExecutable);
    expect(cubit.state.tabs, isEmpty);
    expect(cubit.state.selectedMemberId, isEmpty);

    final team = TeamProfile(
      id: 'test-team',
      name: 'Test',
      members: const [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'dev', name: 'developer'),
      ],
    );

    cubit.syncTeam(team);
    expect(cubit.state.selectedMemberId, 'team-lead');

    cubit.selectMember('dev');
    expect(cubit.state.selectedMemberId, 'dev');
  });

  test('chat cubit opens member shells inside one session tab', () async {
    final postFrame = PostFrameTestHarness();
    final cubit = ChatCubit(
      executableResolver: _testExecutable,
      terminalSessionFactory:
          ({required String executable, int scrollbackLines = 10000}) =>
              FakeTerminalSession(
                executable: executable,
                scrollbackLines: scrollbackLines,
              ),
      postFrameScheduler: postFrame.scheduler,
    );
    final team = TeamProfile(
      id: 'test-team',
      name: 'Test',
      members: const [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'dev', name: 'developer'),
      ],
    );

    await cubit.openMemberTab(team, team.members[0]);
    await cubit.openMemberTab(team, team.members[1]);
    await postFrame.flush();

    expect(cubit.state.tabs.length, 1);
    expect(cubit.state.tabs.single.id, 'local-test-team');
    expect(cubit.state.selectedMemberId, 'dev');
    expect(cubit.isMemberRunning('team-lead'), isTrue);
    expect(cubit.isMemberRunning('dev'), isTrue);
  });

  test(
    'chat cubit launches Claude members with team dir and settings file',
    () async {
      final tmp = await Directory.systemTemp.createTemp('chat_claude_cfg_');
      addTearDown(() => _deleteTempDirBestEffort(tmp));
      final sessions = <FakeTerminalSession>[];
      final postFrame = PostFrameTestHarness();
      final cubit = ChatCubit(
        executableResolver: () => 'claude',
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) {
              final session = FakeTerminalSession(executable: executable);
              sessions.add(session);
              return session;
            },
        postFrameScheduler: postFrame.scheduler,
        lifecycleService: SessionLifecycleService(
          storageRootsResolver: () async => testRuntimeContext(tmp.path),
        ),
      );
      const team = TeamProfile(
        id: 'test-team',
        name: 'Test',
        cli: CliTool.claude,
        members: [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead', model: 'opus'),
          TeamMemberConfig(id: 'dev', name: 'developer', model: 'sonnet'),
        ],
      );

      await cubit.openMemberTab(team, team.members[1]);
      await postFrame.flush();

      expect(sessions, hasLength(1));
      final claudeDir =
          sessions.single.lastExtraEnvironments.single?['CLAUDE_CONFIG_DIR'];
      expect(claudeDir, isNotNull);
      expect(claudeDir, contains(p.join('workspace', 'workspaces')));
      expect(claudeDir, endsWith(p.join('runtime', 'claude')));
      expect(
        sessions
            .single
            .lastExtraEnvironments
            .single?[ClaudeConfigProfileCapability.settingsFileEnvKey],
        p.join(claudeDir!, 'settings', 'dev.json'),
      );
    },
  );

  test(
    'chat cubit connectSession starts all members when auto-launch enabled',
    () async {
      final tmp = await Directory.systemTemp.createTemp('connect_all_');
      addTearDown(() => _deleteTempDirBestEffort(tmp));
      final repo = SessionRepository(rootDir: tmp.path);
      final postFrame = PostFrameTestHarness();
      final team = TeamProfile(
        id: 'test-team',
        name: 'Test',
        members: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'developer'),
        ],
      );
      final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/wd')]);
      await repo.createSession(
        workspace.workspaceId,
        sessionTeam: team.id,
        rosterMembers: team.members,
      );
      final cubit = ChatCubit(
        executableResolver: _testExecutable,
        sessionRepository: repo,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                FakeTerminalSession(
                  executable: executable,
                  scrollbackLines: scrollbackLines,
                ),
        postFrameScheduler: postFrame.scheduler,
        autoLaunchAllMembersOnConnect: () => true,
      );
      addTearDown(() => _tearDownChatCubitWithSessionPersist(cubit, postFrame));
      await cubit.loadWorkspaceData(repo);

      cubit.syncTeam(team);
      await cubit.connectWorkspaceSession(TeamSessionConnect(team), repo: repo);
      await drainPendingAsyncWork();
      await postFrame.flush();

      expect(cubit.state.tabs.length, 1);
      expect(cubit.isMemberRunning('team-lead'), isTrue);
      expect(cubit.isMemberRunning('dev'), isTrue);
      expect(cubit.state.selectedMemberId, 'team-lead');
    },
  );

  test(
    'chat cubit connectSession starts only selected member by default',
    () async {
      final tmp = await Directory.systemTemp.createTemp('connect_one_');
      addTearDown(() => _deleteTempDirBestEffort(tmp));
      final repo = SessionRepository(rootDir: tmp.path);
      final postFrame = PostFrameTestHarness();
      final team = TeamProfile(
        id: 'test-team',
        name: 'Test',
        members: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'developer'),
        ],
      );
      final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/wd')]);
      await repo.createSession(
        workspace.workspaceId,
        sessionTeam: team.id,
        rosterMembers: team.members,
      );
      final cubit = ChatCubit(
        executableResolver: _testExecutable,
        sessionRepository: repo,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                FakeTerminalSession(
                  executable: executable,
                  scrollbackLines: scrollbackLines,
                ),
        postFrameScheduler: postFrame.scheduler,
      );
      addTearDown(() => _tearDownChatCubitWithSessionPersist(cubit, postFrame));
      await cubit.loadWorkspaceData(repo);

      cubit.syncTeam(team);
      await cubit.connectWorkspaceSession(TeamSessionConnect(team), repo: repo);
      await drainPendingAsyncWork();
      await postFrame.flush();

      expect(cubit.state.tabs.length, 1);
      expect(cubit.isMemberRunning('team-lead'), isTrue);
      expect(cubit.isMemberRunning('dev'), isFalse);
      expect(cubit.state.selectedMemberId, 'team-lead');
    },
  );

  test(
    'chat cubit keeps persisted session tabs separate from member selection',
    () async {
      final postFrame = PostFrameTestHarness();
      final cubit = ChatCubit(
        executableResolver: _testExecutable,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                FakeTerminalSession(
                  executable: executable,
                  scrollbackLines: scrollbackLines,
                ),
        postFrameScheduler: postFrame.scheduler,
      );
      final team = TeamProfile(
        id: 'test-team',
        name: 'Test',
        members: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'developer'),
        ],
      );
      final session = AppSession(
        sessionId: 'session-1',
        workspaceId: 'proj-test-2',
        folders: const [WorkspaceFolder(path: '/tmp')],
        display: 'Session One',
        sessionTeam: 'test-team',
        cliTeamName: 'test-team-1',
        members: [
          SessionMemberBinding(
            rosterMemberId: 'team-lead',
            taskId: 'task-lead',
          ),
          SessionMemberBinding(rosterMemberId: 'dev', taskId: 'task-dev'),
        ],
        createdAt: 1,
        updatedAt: 1,
      );

      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: session, team: team,
        member: team.members.first,
        ),
      );
      await drainPendingAsyncWork();
      await cubit.openMemberTab(team, team.members[0]);
      await cubit.openMemberTab(team, team.members[1]);
      await drainPendingAsyncWork();
      await postFrame.flush();

      expect(cubit.state.tabs.length, 1);
      expect(cubit.state.tabs.single.id, 'session-1');
      expect(cubit.state.activeSessionId, 'session-1');
      expect(cubit.state.selectedMemberId, 'dev');
      expect(cubit.isMemberRunning('team-lead'), isTrue);
      expect(cubit.isMemberRunning('dev'), isTrue);
    },
  );

  test('openSessionTab first launch uses session-id not resume', () async {
    final tmp = await Directory.systemTemp.createTemp('open_sess_');
    addTearDown(() => _deleteTempDirBestEffort(tmp));
    final repo = SessionRepository(rootDir: tmp.path);
    final team = TeamProfile(
      id: 'tid',
      name: 'TName',
      members: const [TeamMemberConfig(id: 'lid', name: 'team-lead')],
    );
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/wd')]);
    await repo.createSession(
      workspace.workspaceId,
      sessionTeam: team.id,
      rosterMembers: team.members,
    );
    FakeTerminalSession? captured;
    final postFrame = PostFrameTestHarness();
    final cubit = ChatCubit(
      executableResolver: _testExecutable,
      terminalSessionFactory:
          ({required String executable, int scrollbackLines = 10000}) {
            captured = FakeTerminalSession(executable: executable);
            return captured!;
          },
      postFrameScheduler: postFrame.scheduler,
    );
    addTearDown(() => _tearDownChatCubitWithSessionPersist(cubit, postFrame));
    await cubit.loadWorkspaceData(repo);
    final rel = cubit.state.sessions.single;
    await cubit.requestOpenSession(
        SessionOpenRequest(
          session: rel, team: team,
      member: team.members.first,
      repo: repo,
        ),
      );
    await drainPendingAsyncWork();
    await postFrame.flush();
    await drainPendingAsyncWork();
    expect(captured, isNotNull);
    expect(captured!.lastResumeSessionIds.last, isNull);
    expect(captured!.lastFixedSessionIds.last, rel.members.single.taskId);
  });

  test('openSessionTab started session uses resume not session-id', () async {
    final tmp = await Directory.systemTemp.createTemp('open_sess_');
    addTearDown(() => _deleteTempDirBestEffort(tmp));
    final repo = SessionRepository(rootDir: tmp.path);
    final team = TeamProfile(
      id: 'tid',
      name: 'TName',
      members: const [TeamMemberConfig(id: 'lid', name: 'team-lead')],
    );
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/wd')]);
    final session = await repo.createSession(
      workspace.workspaceId,
      sessionTeam: team.id,
      rosterMembers: team.members,
    );
    await repo.markSessionLaunched(session.sessionId);

    FakeTerminalSession? captured;
    final postFrame = PostFrameTestHarness();
    final cubit = ChatCubit(
      executableResolver: _testExecutable,
      terminalSessionFactory:
          ({required String executable, int scrollbackLines = 10000}) {
            captured = FakeTerminalSession(executable: executable);
            return captured!;
          },
      postFrameScheduler: postFrame.scheduler,
      lifecycleService: _FixedResumeLifecycleService(resume: true),
    );
    addTearDown(() => _tearDownChatCubitWithSessionPersist(cubit, postFrame));
    await cubit.loadWorkspaceData(repo);
    final rel = cubit.state.sessions.single;
    await cubit.requestOpenSession(
        SessionOpenRequest(
          session: rel, team: team,
      member: team.members.first,
      repo: repo,
        ),
      );
    await drainPendingAsyncWork();
    await postFrame.flush();
    expect(captured!.lastResumeSessionIds.last, rel.members.single.taskId);
    expect(captured!.lastFixedSessionIds.last, isNull);
  });

  test(
    'openSessionTab started session without CLI descriptor uses session-id',
    () async {
      final tmp = await Directory.systemTemp.createTemp('open_sess_');
      addTearDown(() => _deleteTempDirBestEffort(tmp));
      final repo = SessionRepository(rootDir: tmp.path);
      final team = TeamProfile(
        id: 'tid',
        name: 'TName',
        members: const [TeamMemberConfig(id: 'lid', name: 'team-lead')],
      );
      final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/wd')]);
      final session = await repo.createSession(
        workspace.workspaceId,
        sessionTeam: team.id,
        rosterMembers: team.members,
      );
      await repo.markSessionLaunched(session.sessionId);

      FakeTerminalSession? captured;
      final postFrame = PostFrameTestHarness();
      final cubit = ChatCubit(
        executableResolver: _testExecutable,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) {
              captured = FakeTerminalSession(executable: executable);
              return captured!;
            },
        postFrameScheduler: postFrame.scheduler,
        lifecycleService: _FixedResumeLifecycleService(resume: false),
      );
      addTearDown(() => _tearDownChatCubitWithSessionPersist(cubit, postFrame));
      await cubit.loadWorkspaceData(repo);
      final rel = cubit.state.sessions.single;
      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: rel, team: team,
        member: team.members.first,
        repo: repo,
        ),
      );
      await drainPendingAsyncWork();
      await postFrame.flush();
      expect(captured!.lastResumeSessionIds.last, isNull);
      expect(captured!.lastFixedSessionIds.last, rel.members.single.taskId);
    },
  );

  test(
    'openSessionTab passes session additionalDirectories to connect',
    () async {
      final tmp = await Directory.systemTemp.createTemp('open_sess_');
      addTearDown(() => _deleteTempDirBestEffort(tmp));
      final repo = SessionRepository(rootDir: tmp.path);
      final team = TeamProfile(
        id: 'tid',
        name: 'TName',
        members: const [TeamMemberConfig(id: 'lid', name: 'team-lead')],
      );
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/root'),
        WorkspaceFolder(path: '/extra'),
      ]);
      await repo.createSession(
        workspace.workspaceId,
        sessionTeam: team.id,
        rosterMembers: team.members,
      );
      FakeTerminalSession? captured;
      final postFrame = PostFrameTestHarness();
      final cubit = ChatCubit(
        executableResolver: _testExecutable,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) {
              captured = FakeTerminalSession(executable: executable);
              return captured!;
            },
        postFrameScheduler: postFrame.scheduler,
      );
      addTearDown(() => _tearDownChatCubitWithSessionPersist(cubit, postFrame));
      await cubit.loadWorkspaceData(repo);
      final rel = cubit.state.sessions.single;
      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: rel, team: team,
        member: team.members.first,
        repo: repo,
        ),
      );
      await drainPendingAsyncWork();
      await postFrame.flush();
      expect(captured!.lastAdditionalDirectoriesLists.last, ['/extra']);
    },
  );

  test('llm config cubit manages providers and models', () async {
    final cubit = testLlmConfigCubit(
      initialConfig: const LlmConfig(
        providers: {
          'test': LlmProviderConfig(
            name: 'test',
            type: 'api',
            providerType: 'openai',
          ),
        },
      ),
    );

    expect(cubit.state.config.providers.length, 1);

    cubit.addProvider(
      const LlmProviderConfig(name: 'new', type: 'account', providerType: ''),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.config.providers.length, 2);

    cubit.addModel(
      const LlmModelConfig(
        id: 'm1',
        name: 'Model 1',
        provider: 'test',
        model: 'gpt-4',
        enabled: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.config.models.length, 1);

    cubit.deleteProvider('new');
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.config.providers.length, 1);
  });
}
