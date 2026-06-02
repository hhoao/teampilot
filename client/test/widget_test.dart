import 'dart:io';

import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/config_cubit.dart';
import 'package:teampilot/cubits/extension_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/llm_config_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/team_cubit.dart';
import 'package:teampilot/main.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/models/llm_config.dart';
import 'package:teampilot/models/app_project.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/layout_repository.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/extension_repository.dart';
import 'package:teampilot/repositories/team_repository.dart';
import 'package:teampilot/services/extension/builtin_manifests.dart';
import 'package:teampilot/services/extension/extension_acquisition_engine.dart';
import 'package:teampilot/services/extension/extension_detector.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/models/connection_mode.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/flashskyai_storage_roots.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
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

ExtensionCubit _testExtensionCubit() => ExtensionCubit(
      ExtensionRepository(
        fs: InMemoryFilesystem(),
        stateFilePath: '/test/extensions/state.json',
        manifests: builtInExtensionManifests(),
      ),
      ExtensionAcquisitionEngine(
        runner: (c) async => const CliInstallerCommandResult(exitCode: 0),
      ),
      detector: ExtensionDetector(processRunner: (e, a, {environment}) async => ProcessResult(0, 1, '', '')),
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

Widget buildTestApp({
  required TeamCubit teamCubit,
  required SessionPreferencesCubit sessionPreferencesCubit,
  ChatCubit? chatCubit,
  LayoutCubit? layoutCubit,
  LlmConfigCubit? llmConfigCubit,
  AppProviderCubit? appProviderCubit,
  AppSettingsRepository? appSettings,
  ExtensionCubit? extensionCubit,
}) {
  final connectionModeService = ConnectionModeService(
    readPreferredMode: () => ConnectionMode.localPty,
    hasSshProfiles: () => true,
  );
  final settings =
      appSettings ??
      InMemoryAppSettingsRepository(hasCompletedOnboarding: true);

  return MultiRepositoryProvider(
    providers: [
      RepositoryProvider<AppSettingsRepository>.value(value: settings),
      RepositoryProvider<SessionRepository>.value(
        value: _widgetTestSessionRepo,
      ),
      RepositoryProvider<ConnectionModeService>.value(
        value: connectionModeService,
      ),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider.value(value: teamCubit),
        BlocProvider.value(
          value: chatCubit ?? ChatCubit(executableResolver: _testExecutable),
        ),
        BlocProvider(create: (_) => ConfigCubit()),
        BlocProvider.value(value: llmConfigCubit ?? testLlmConfigCubit()),
        BlocProvider.value(value: appProviderCubit!),
        BlocProvider.value(value: layoutCubit ?? LayoutCubit()),
        BlocProvider.value(value: sessionPreferencesCubit),
        BlocProvider(create: (_) => EditorCubit(fs: LocalFilesystem())),
        BlocProvider.value(value: extensionCubit ?? _testExtensionCubit()),
      ],
      child: const TeamPilotApp(),
    ),
  );
}

/// [TeamPilotApp] shares the process-wide [appRouter]. Widget tests that
/// navigate to settings must reset the location so later tests see `/chat`.
void resetAppRouterLocationForWidgetTests() {
  final location = appRouter.routerDelegate.currentConfiguration.uri.path;
  if (location != '/chat') {
    appRouter.go('/chat');
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
  TeamCubit teamCubit, {
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

Future<TeamCubit> createTeamCubit({TeamLauncher? launcher}) async {
  final tmp = await Directory.systemTemp.createTemp('teams_widget_');
  final appData = await Directory.systemTemp.createTemp('teams_widget_app_');
  final repository = TeamRepository(rootDir: tmp.path);
  final cubit = TeamCubit(
    repository: repository,
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
Future<TeamCubit> createTeamCubitInTest(
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
    TeamConfig? team,
    TeamMemberConfig? member,
    String? sessionTeam,
    Map<String, String>? extraEnvironment,
    void Function()? onProcessStarted,
    void Function(String message)? onProcessFailed,
    void Function()? onProcessExited,
    void Function(String line)? onFirstUserLineSubmitted,
    BusUserInputRouting? busUserInputRouting,
  }) {
    lastFixedSessionIds.add(fixedSessionId);
    lastResumeSessionIds.add(resumeSessionId);
    lastAdditionalDirectoriesLists.add(
      List<String>.from(additionalDirectories),
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
  Future<LaunchPlan> prepareLaunch({
    required AppSession session,
    TeamConfig? team,
    TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    String? llmConfigPathOverride,
    Map<String, Map<String, Object?>>? extraMcpServers,
    String? busIdleUrl,
  }) async {
    final taskId = memberBinding?.taskId ?? session.sessionId;
    final cliTeamName = session.cliTeamName.trim().isNotEmpty
        ? session.cliTeamName.trim()
        : session.sessionId;
    return LaunchPlan(
      env: const {},
      resume: resume,
      taskId: taskId,
      cliTeamName: cliTeamName,
      memberConfigDir: '',
      resolvedRoots: const [],
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
            lifecycleService ??
            _FixedResumeLifecycleService(resume: false),
      );

  factory TestChatCubit() {
    final harness = PostFrameTestHarness();
    return TestChatCubit._(harness, sessionRepository: _widgetTestSessionRepo);
  }

  final PostFrameTestHarness postFrame;

  void seedChatData({
    List<AppProject> projects = const [],
    List<AppSession> sessions = const [],
  }) {
    ingestProjectSessionSnapshot(projects: projects, sessions: sessions);
  }
}

void main() {
  setUpAll(() async {
    _widgetTestSessionRepoDir = await Directory.systemTemp.createTemp(
      'widget_sess_repo_',
    );
    _widgetTestSessionRepo = SessionRepository(
      rootDir: _widgetTestSessionRepoDir.path,
    );
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

  testWidgets('renders chat workbench shell on initial route', (tester) async {
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
    await pumpDesktopApp(tester, teamCubit, chatCubit: chatCubit);
    await tester.pump();
    await pumpPhaseTransitions(tester);

    expect(find.byKey(AppKeys.contextSidebar), findsOneWidget);
    expect(find.byKey(AppKeys.chatWorkspace), findsOneWidget);
    expect(find.byKey(AppKeys.rightToolsPanel), findsOneWidget);
    expect(find.byKey(AppKeys.membersPanel), findsOneWidget);
    expect(find.byKey(AppKeys.fileTreePanel), findsOneWidget);
    expect(find.text('Default Team'), findsWidgets);
    final sidebarCtx = tester.element(find.byKey(AppKeys.contextSidebar));
    expect(find.text(AppLocalizations.of(sidebarCtx).projects), findsOneWidget);
    expect(find.text('team-lead'), findsWidgets);
    expect(chatCubit.state.tabs.length, 0);
    final workbenchCtx = tester.element(find.byKey(AppKeys.chatWorkspace));
    final l10n = AppLocalizations.of(workbenchCtx);
    expect(find.text(l10n.sessionReadyTitle), findsOneWidget);
    expect(
      find.text(l10n.sessionReadySubtitle('team-lead')),
      findsOneWidget,
    );

    final selectedTeam = teamCubit.state.selectedTeam;
    expect(selectedTeam, isNotNull);
    // Real repository I/O must run inside runAsync in widget tests.
    await tester.runAsync(
      () => chatCubit.connectSession(selectedTeam!),
    );
    await tester.pump();
    await tester.runAsync(postFrame.flush);
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

    await tester.tap(find.byKey(AppKeys.sidebarSettingsButton));
    await pumpPhaseTransitions(tester);

    expect(
      find.text('Manage FlashskyAI team and model settings.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.groups_2_outlined), findsOneWidget);
    expect(find.byIcon(Icons.memory_outlined), findsOneWidget);
  });

  testWidgets('settings pages use the global component theme', (tester) async {
    final teamCubit = await createTeamCubitInTest(tester);
    await pumpDesktopApp(tester, teamCubit);

    await tester.tap(find.byKey(AppKeys.sidebarSettingsButton));
    await pumpPhaseTransitions(tester);

    final settingsCtx = tester.element(find.byKey(AppKeys.configWorkspace));
    final settingsTheme = Theme.of(settingsCtx);
    final cs = settingsTheme.colorScheme;
    expect(cs.primary, themePresetSwatchPrimary(kDefaultThemeColorPreset));
    expect(settingsTheme.filledButtonTheme.style, isNotNull);

    await tester.tap(find.byKey(AppKeys.configLlmSectionButton));
    await pumpPhaseTransitions(tester);

    final providerList = tester.widget<Material>(
      find.byKey(AppKeys.llmProviderList),
    );
    expect(providerList.color, cs.surfaceContainer);
  });

  testWidgets('desktop add provider opens form in detail area', (tester) async {
    final teamCubit = await createTeamCubitInTest(tester);
    await pumpDesktopApp(tester, teamCubit);

    await tester.tap(find.byKey(AppKeys.sidebarSettingsButton));
    await pumpPhaseTransitions(tester);
    await tester.tap(find.byKey(AppKeys.configLlmSectionButton));
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

  testWidgets('session settings configure Claude Code CLI path', (
    tester,
  ) async {
    final teamCubit = await createTeamCubitInTest(tester);
    final sessionCubit = await tester.runAsync(testSessionPreferencesCubit);
    expect(sessionCubit, isNotNull);
    await sessionCubit!.load();

    await pumpDesktopApp(
      tester,
      teamCubit,
      sessionPreferencesCubit: sessionCubit,
    );

    await tester.tap(find.byKey(AppKeys.sidebarSettingsButton));
    await pumpPhaseTransitions(tester);
    await tester.tap(find.byKey(AppKeys.configSessionSectionButton));
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
    final team = TeamConfig(
      id: 'default-team',
      name: 'Default Team',
      members: TeamMemberNaming.defaultRoster(),
    );
    final postFrame = PostFrameTestHarness();
    final repo = SessionRepository(rootDir: (await Directory.systemTemp.createTemp('sidebar_sess_')).path);
    final project = await repo.createProject('/work/current');
    final session = await repo.createSession(
      project.projectId,
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
    await chatCubit.loadProjectData(repo);

    await chatCubit.openSessionTab(
      session,
      team: team,
      member: team.members.first,
      repo: repo,
    );
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
    final repository = TeamRepository(rootDir: tmp.path);
    final cubit = TeamCubit(
      repository: repository,
      executableResolver: _testExecutable,
      appDataBasePath: appData.path,
      configProfileService: ConfigProfileService(basePath: appData.path),
    );
    await cubit.load();

    expect(cubit.state.selectedTeam?.name, 'Default Team');
    expect(cubit.state.teams.length, 1);
    expect(cubit.state.selectedTeam?.members.length, 3);
    expect(
      cubit.state.selectedTeam?.members.map((m) => m.id).toList(),
      ['team-lead', 'developer', 'reviewer'],
    );

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

    expect(cubit.state.preferences.toolPlacement, ToolPanelPlacement.right);

    await cubit.setToolPlacement(ToolPanelPlacement.bottom);
    expect(cubit.state.preferences.toolPlacement, ToolPanelPlacement.bottom);

    await cubit.setThemeMode('dark');
    expect(cubit.state.preferences.themeMode, 'dark');
  });

  test('config cubit navigates sections', () {
    final cubit = ConfigCubit();
    expect(cubit.state.section, ConfigSection.layout);

    cubit.selectSection(ConfigSection.llm);
    expect(cubit.state.section, ConfigSection.llm);

    cubit.selectSection(ConfigSection.layout);
    expect(cubit.state.section, ConfigSection.layout);
  });

  test('chat cubit manages tabs and selection', () {
    final cubit = ChatCubit(executableResolver: _testExecutable);
    expect(cubit.state.tabs, isEmpty);
    expect(cubit.state.selectedMemberId, isEmpty);

    final team = TeamConfig(
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
    final team = TeamConfig(
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
          storageRootsResolver: () async => StorageRootsSnapshot(
            storageIsRemote: false,
            teampilotRoot: tmp.path,
            teamsUiDir: p.join(tmp.path, 'teams'),
            skillsRoot: p.join(tmp.path, 'skills', 'installed'),
            skillBackupsDir: p.join(tmp.path, 'skills', 'backups'),
            appProjectsDir: p.join(tmp.path, 'projects'),
            skillReposConfigPath: p.join(tmp.path, 'skills', 'repos.json'),
            pluginsRoot: p.join(tmp.path, 'plugins', 'installed'),
            pluginBackupsDir: p.join(tmp.path, 'plugins', 'backups'),
            pluginsJsonPath: p.join(tmp.path, 'plugins', 'plugins.json'),
            pluginMarketplacesConfigPath:
                p.join(tmp.path, 'plugins', 'marketplaces.json'),
            pluginMarketplaceCacheDir:
                p.join(tmp.path, 'plugins', 'marketplace-cache'),
            pluginExternalCacheDir: p.join(tmp.path, 'plugins', 'external-cache'),
            mcpServersJsonPath: p.join(tmp.path, 'mcp', 'mcp_servers.json'),
            mcpRegistrySourcesConfigPath:
                p.join(tmp.path, 'mcp', 'registry_sources.json'),
          ),
        ),
      );
      const team = TeamConfig(
        id: 'test-team',
        name: 'Test',
        cli: TeamCli.claude,
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
      final sessionId = p.basename(p.dirname(claudeDir!));
      expect(
        sessionId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(
        claudeDir,
        p.join(
          tmp.path,
          'config-profiles',
          'teams',
          'test-team',
          'members',
          sessionId,
          'claude',
        ),
      );
      expect(
        sessions.single.lastExtraEnvironments.single?[ConfigProfileService
            .claudeSettingsFileEnvKey],
        p.join(
          tmp.path,
          'config-profiles',
          'teams',
          'test-team',
          'members',
          sessionId,
          'claude',
          'settings',
          'dev.json',
        ),
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
      final team = TeamConfig(
        id: 'test-team',
        name: 'Test',
        members: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'developer'),
        ],
      );
      final project = await repo.createProject('/wd');
      await repo.createSession(
        project.projectId,
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
      await cubit.loadProjectData(repo);

      cubit.syncTeam(team);
      await cubit.connectSession(team, repo: repo);
      await postFrame.flush();
      await drainPendingAsyncWork();

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
      final team = TeamConfig(
        id: 'test-team',
        name: 'Test',
        members: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'developer'),
        ],
      );
      final project = await repo.createProject('/wd');
      await repo.createSession(
        project.projectId,
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
      await cubit.loadProjectData(repo);

      cubit.syncTeam(team);
      await cubit.connectSession(team, repo: repo);
      await postFrame.flush();
      await drainPendingAsyncWork();

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
      final team = TeamConfig(
        id: 'test-team',
        name: 'Test',
        members: const [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'developer'),
        ],
      );
      const session = AppSession(
        sessionId: 'session-1',
        projectId: 'proj-test-2',
        primaryPath: '/tmp',
        display: 'Session One',
        sessionTeam: 'test-team',
        cliTeamName: 'test-team-1',
        members: [
          SessionMemberBinding(rosterMemberId: 'team-lead', taskId: 'task-lead'),
          SessionMemberBinding(rosterMemberId: 'dev', taskId: 'task-dev'),
        ],
        createdAt: 1,
        updatedAt: 1,
      );

      await cubit.openSessionTab(
        session,
        team: team,
        member: team.members.first,
      );
      await cubit.openMemberTab(team, team.members[0]);
      await cubit.openMemberTab(team, team.members[1]);
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
    final project = await repo.createProject('/wd');
    final team = TeamConfig(
      id: 'tid',
      name: 'TName',
      members: const [TeamMemberConfig(id: 'lid', name: 'team-lead')],
    );
    await repo.createSession(
      project.projectId,
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
    await cubit.loadProjectData(repo);
    final rel = cubit.state.sessions.single;
    await cubit.openSessionTab(
      rel,
      team: team,
      member: team.members.first,
      repo: repo,
    );
    await postFrame.flush();
    await drainPendingAsyncWork();
    expect(captured, isNotNull);
    expect(captured!.lastResumeSessionIds.last, isNull);
    expect(
      captured!.lastFixedSessionIds.last,
      rel.members.single.taskId,
    );
  });

  test('openSessionTab started session uses resume not session-id', () async {
    final tmp = await Directory.systemTemp.createTemp('open_sess_');
    addTearDown(() => _deleteTempDirBestEffort(tmp));
    final repo = SessionRepository(rootDir: tmp.path);
    final project = await repo.createProject('/wd');
    final team = TeamConfig(
      id: 'tid',
      name: 'TName',
      members: const [TeamMemberConfig(id: 'lid', name: 'team-lead')],
    );
    final session = await repo.createSession(
      project.projectId,
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
    await cubit.loadProjectData(repo);
    final rel = cubit.state.sessions.single;
    await cubit.openSessionTab(
      rel,
      team: team,
      member: team.members.first,
      repo: repo,
    );
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
      final project = await repo.createProject('/wd');
      final team = TeamConfig(
        id: 'tid',
        name: 'TName',
        members: const [TeamMemberConfig(id: 'lid', name: 'team-lead')],
      );
      final session = await repo.createSession(
        project.projectId,
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
      await cubit.loadProjectData(repo);
      final rel = cubit.state.sessions.single;
      await cubit.openSessionTab(
        rel,
        team: team,
        member: team.members.first,
        repo: repo,
      );
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
      final project = await repo.createProject(
        '/root',
        additionalPaths: const ['/extra'],
      );
      final team = TeamConfig(
        id: 'tid',
        name: 'TName',
        members: const [TeamMemberConfig(id: 'lid', name: 'team-lead')],
      );
      await repo.createSession(
        project.projectId,
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
      await cubit.loadProjectData(repo);
      final rel = cubit.state.sessions.single;
      await cubit.openSessionTab(
        rel,
        team: team,
        member: team.members.first,
        repo: repo,
      );
      await postFrame.flush();
      await drainPendingAsyncWork();
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
