import 'dart:io';

import 'package:flashskyai_client/l10n/app_localizations.dart';
import 'package:flashskyai_client/cubits/chat_cubit.dart';
import 'package:flashskyai_client/cubits/config_cubit.dart';
import 'package:flashskyai_client/cubits/layout_cubit.dart';
import 'package:flashskyai_client/cubits/llm_config_cubit.dart';
import 'package:flashskyai_client/cubits/session_preferences_cubit.dart';
import 'package:flashskyai_client/cubits/team_cubit.dart';
import 'package:flashskyai_client/main.dart';
import 'package:flashskyai_client/models/layout_preferences.dart';
import 'package:flashskyai_client/models/llm_config.dart';
import 'package:flashskyai_client/models/app_project.dart';
import 'package:flashskyai_client/models/app_session.dart';
import 'package:flashskyai_client/models/team_config.dart';
import 'package:flashskyai_client/repositories/app_settings_repository.dart';
import 'package:flashskyai_client/repositories/layout_repository.dart';
import 'package:flashskyai_client/repositories/session_preferences_repository.dart';
import 'package:flashskyai_client/repositories/session_repository.dart';
import 'package:flashskyai_client/repositories/team_repository.dart';
import 'package:flashskyai_client/services/terminal_session.dart';
import 'package:flashskyai_client/theme/app_theme.dart';
import 'package:flashskyai_client/utils/app_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _testExecutable() => 'flashskyai';

late Directory _widgetTestSessionRepoDir;
late SessionRepository _widgetTestSessionRepo;

Widget buildTestApp({
  required TeamCubit teamCubit,
  required SessionPreferencesCubit sessionPreferencesCubit,
  ChatCubit? chatCubit,
  LayoutCubit? layoutCubit,
  LlmConfigCubit? llmConfigCubit,
}) {
  return RepositoryProvider<SessionRepository>.value(
    value: _widgetTestSessionRepo,
    child: MultiBlocProvider(
      providers: [
        BlocProvider.value(value: teamCubit),
        BlocProvider.value(
            value: chatCubit ?? ChatCubit(executableResolver: _testExecutable)),
        BlocProvider(create: (_) => ConfigCubit()),
        BlocProvider.value(value: llmConfigCubit ?? testLlmConfigCubit()),
        BlocProvider.value(value: layoutCubit ?? LayoutCubit()),
        BlocProvider.value(value: sessionPreferencesCubit),
      ],
      child: const FlashskyAiClientApp(),
    ),
  );
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
  SessionPreferencesCubit? sessionPreferencesCubit,
}) async {
  tester.view.physicalSize = const Size(1200, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final sessionCubit = sessionPreferencesCubit ??
      (await tester.runAsync(testSessionPreferencesCubit))!;
  await tester.pumpWidget(
    buildTestApp(
      teamCubit: teamCubit,
      sessionPreferencesCubit: sessionCubit,
      chatCubit: chatCubit,
      layoutCubit: layoutCubit,
      llmConfigCubit: llmConfigCubit,
    ),
  );
  // Avoid pumpAndSettle: router + split-view can schedule frames indefinitely in tests.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

LlmConfigCubit testLlmConfigCubit({LlmConfig initialConfig = const LlmConfig()}) {
  return LlmConfigCubit(
    appSettings: InMemoryAppSettingsRepository(),
    currentDirectory: Directory.systemTemp.path,
    homeDirectory: '/tmp',
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
  final cliTmp = await Directory.systemTemp.createTemp('teams_widget_cli_');
  final repository =
      TeamRepository(rootDir: tmp.path, cliTeamsDir: cliTmp.path);
  final cubit = TeamCubit(
    repository: repository,
    executableResolver: _testExecutable,
    launcher: launcher ?? (_, __) async {},
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
  final cubit = await tester.runAsync(() => createTeamCubit(launcher: launcher));
  expect(cubit, isNotNull);
  return cubit!;
}

class FakeTerminalSession extends TerminalSession {
  FakeTerminalSession({String executable = 'flashskyai'})
      : super(executable: executable);

  var _running = false;
  final connectedMembers = <String>[];
  final resumedSessions = <String>[];
  final lastFixedSessionIds = <String?>[];
  final lastResumeSessionIds = <String?>[];
  final lastAdditionalDirectoriesLists = <List<String>>[];

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
  }) {
    lastFixedSessionIds.add(fixedSessionId);
    lastResumeSessionIds.add(resumeSessionId);
    lastAdditionalDirectoriesLists.add(List<String>.from(additionalDirectories));
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

class TestChatCubit extends ChatCubit {
  TestChatCubit()
    : super(
        executableResolver: _testExecutable,
        terminalSessionFactory: FakeTerminalSession.new,
        postFrameScheduler: (callback) => callback(),
      );

  void seedChatData({
    List<AppProject> projects = const [],
    List<AppSession> sessions = const [],
  }) {
    ingestProjectSessionSnapshot(projects: projects, sessions: sessions);
  }
}

void main() {
  setUpAll(() async {
    _widgetTestSessionRepoDir =
        await Directory.systemTemp.createTemp('widget_sess_repo_');
    _widgetTestSessionRepo =
        SessionRepository(rootDir: _widgetTestSessionRepoDir.path);
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
  });

  testWidgets('renders chat workbench shell on initial route', (tester) async {
    final teamCubit = await createTeamCubitInTest(tester);
    final chatCubit = ChatCubit(
      executableResolver: _testExecutable,
      terminalSessionFactory: FakeTerminalSession.new,
      postFrameScheduler: (callback) => callback(),
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
    expect(
      find.text(AppLocalizations.of(sidebarCtx).projects),
      findsOneWidget,
    );
    expect(find.text('team-lead'), findsWidgets);
    expect(chatCubit.state.tabs.length, 0);
    expect(find.text('Terminal not connected'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (chatCubit.state.tabs.isNotEmpty) break;
    }
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

    final settingsTheme = Theme.of(
      tester.element(find.byKey(AppKeys.configWorkspace)),
    );
    final appColors = AppColors.of(
      tester.element(find.byKey(AppKeys.configWorkspace)),
    );
    final filledButtonColor = settingsTheme
        .filledButtonTheme
        .style
        ?.backgroundColor
        ?.resolve(<WidgetState>{});
    expect(filledButtonColor, appColors.accentBlue);

    await tester.tap(find.byKey(AppKeys.configLlmSectionButton));
    await pumpPhaseTransitions(tester);

    final providerList = tester.widget<Container>(
      find.byKey(AppKeys.llmProviderList),
    );
    final decoration = providerList.decoration! as BoxDecoration;
    expect(decoration.color, appColors.cardBackground);
  });

  testWidgets('opening a sidebar session starts team-lead member shell', (
    tester,
  ) async {
    final teamCubit = await createTeamCubitInTest(tester);
    final chatCubit = TestChatCubit();
    const projectId = 'proj-test-1';
    chatCubit.seedChatData(
      projects: const [
        AppProject(
          projectId: projectId,
          primaryPath: '/work/current',
          createdAt: 1,
          updatedAt: 1,
          sessionIds: ['session-1'],
        ),
      ],
      sessions: const [
        AppSession(
          sessionId: 'session-1',
          projectId: projectId,
          primaryPath: '/work/current',
          display: 'Session One',
          createdAt: 1,
          updatedAt: 1,
        ),
      ],
    );

    await pumpDesktopApp(tester, teamCubit, chatCubit: chatCubit);

    await tester.tap(find.byKey(AppKeys.sessionTile('session-1')));
    await tester.pump();

    expect(chatCubit.state.activeSessionId, 'session-1');
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
    final cliTmp = await Directory.systemTemp.createTemp('teams_cubit_cli_');
    final repository =
        TeamRepository(rootDir: tmp.path, cliTeamsDir: cliTmp.path);
    final cubit = TeamCubit(
      repository: repository,
      executableResolver: _testExecutable,
    );
    await cubit.load();

    expect(cubit.state.selectedTeam?.name, 'Default Team');
    expect(cubit.state.teams.length, 1);

    cubit.selectTeam('Default Team');
    expect(cubit.state.selectedTeam?.name, 'Default Team');

    await cubit.addMember();
    expect(cubit.state.selectedTeam?.members.length, 2);
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
        TeamMemberConfig(id: 'lead', name: 'team-lead'),
        TeamMemberConfig(id: 'dev', name: 'developer'),
      ],
    );

    cubit.syncTeam(team);
    expect(cubit.state.selectedMemberId, 'lead');

    cubit.selectMember('dev');
    expect(cubit.state.selectedMemberId, 'dev');
  });

  test('chat cubit opens member shells inside one session tab', () async {
    final cubit = ChatCubit(
      executableResolver: _testExecutable,
      terminalSessionFactory: FakeTerminalSession.new,
      postFrameScheduler: (callback) => callback(),
    );
    final team = TeamConfig(
      id: 'test-team',
      name: 'Test',
      members: const [
        TeamMemberConfig(id: 'lead', name: 'team-lead'),
        TeamMemberConfig(id: 'dev', name: 'developer'),
      ],
    );

    await cubit.openMemberTab(team, team.members[0]);
    await cubit.openMemberTab(team, team.members[1]);

    expect(cubit.state.tabs.length, 1);
    expect(cubit.state.tabs.single.id, 'local-test-team');
    expect(cubit.state.selectedMemberId, 'dev');
    expect(cubit.isMemberRunning('lead'), isTrue);
    expect(cubit.isMemberRunning('dev'), isTrue);
  });

  test(
    'chat cubit connectSession starts all members when auto-launch enabled',
    () async {
      final cubit = ChatCubit(
        executableResolver: _testExecutable,
        terminalSessionFactory: FakeTerminalSession.new,
        postFrameScheduler: (callback) => callback(),
        autoLaunchAllMembersOnConnect: () => true,
      );
      final team = TeamConfig(
        id: 'test-team',
        name: 'Test',
        members: const [
          TeamMemberConfig(id: 'lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'developer'),
        ],
      );

      cubit.syncTeam(team);
      await cubit.connectSession(team);

      expect(cubit.state.tabs.length, 1);
      expect(cubit.isMemberRunning('lead'), isTrue);
      expect(cubit.isMemberRunning('dev'), isTrue);
      expect(cubit.state.selectedMemberId, 'lead');
    },
  );

  test(
    'chat cubit connectSession starts only selected member by default',
    () async {
      final cubit = ChatCubit(
        executableResolver: _testExecutable,
        terminalSessionFactory: FakeTerminalSession.new,
        postFrameScheduler: (callback) => callback(),
      );
      final team = TeamConfig(
        id: 'test-team',
        name: 'Test',
        members: const [
          TeamMemberConfig(id: 'lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'developer'),
        ],
      );

      cubit.syncTeam(team);
      await cubit.connectSession(team);

      expect(cubit.state.tabs.length, 1);
      expect(cubit.isMemberRunning('lead'), isTrue);
      expect(cubit.isMemberRunning('dev'), isFalse);
      expect(cubit.state.selectedMemberId, 'lead');
    },
  );

  test(
    'chat cubit keeps persisted session tabs separate from member selection',
    () async {
      final cubit = ChatCubit(
        executableResolver: _testExecutable,
        terminalSessionFactory: FakeTerminalSession.new,
        postFrameScheduler: (callback) => callback(),
      );
      const projectId = 'proj-test-2';
      const session = AppSession(
        sessionId: 'session-1',
        projectId: projectId,
        primaryPath: '/tmp',
        display: 'Session One',
        createdAt: 1,
        updatedAt: 1,
      );
      final team = TeamConfig(
        id: 'test-team',
        name: 'Test',
        members: const [
          TeamMemberConfig(id: 'lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'developer'),
        ],
      );

      cubit.openSessionTab(session);
      await cubit.openMemberTab(team, team.members[0]);
      await cubit.openMemberTab(team, team.members[1]);

      expect(cubit.state.tabs.length, 1);
      expect(cubit.state.tabs.single.id, 'session-1');
      expect(cubit.state.activeSessionId, 'session-1');
      expect(cubit.state.selectedMemberId, 'dev');
      expect(cubit.isMemberRunning('lead'), isTrue);
      expect(cubit.isMemberRunning('dev'), isTrue);
    },
  );

  test('openSessionTab first launch uses session-id not resume', () async {
    final tmp = await Directory.systemTemp.createTemp('open_sess_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);
    final project = await repo.createProject('/wd');
    final session = await repo.createSession(project.projectId);
    FakeTerminalSession? captured;
    final cubit = ChatCubit(
      executableResolver: _testExecutable,
      terminalSessionFactory: ({required String executable}) {
        captured = FakeTerminalSession(executable: executable);
        return captured!;
      },
      postFrameScheduler: (c) => c(),
    );
    await cubit.loadProjectData(repo);
    final team = TeamConfig(
      id: 'tid',
      name: 'TName',
      members: const [
        TeamMemberConfig(id: 'lid', name: 'team-lead'),
      ],
    );
    cubit.openSessionTab(
      session,
      team: team,
      member: team.members.first,
      repo: repo,
    );
    expect(captured, isNotNull);
    expect(captured!.lastResumeSessionIds.last, isNull);
    expect(captured!.lastFixedSessionIds.last, session.sessionId);
  });

  test('openSessionTab started session uses resume not session-id', () async {
    final tmp = await Directory.systemTemp.createTemp('open_sess_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);
    final project = await repo.createProject('/wd');
    final session = await repo.createSession(project.projectId);
    await repo.markSessionLaunched(session.sessionId, launchTeam: 'cli-t');

    FakeTerminalSession? captured;
    final cubit = ChatCubit(
      executableResolver: _testExecutable,
      terminalSessionFactory: ({required String executable}) {
        captured = FakeTerminalSession(executable: executable);
        return captured!;
      },
      postFrameScheduler: (c) => c(),
      cliSessionDescriptorExists: (_, __) => true,
    );
    await cubit.loadProjectData(repo);
    final rel = cubit.state.sessions.single;
    final team = TeamConfig(
      id: 'tid',
      name: 'TName',
      members: const [
        TeamMemberConfig(id: 'lid', name: 'team-lead'),
      ],
    );
    cubit.openSessionTab(
      rel,
      team: team,
      member: team.members.first,
      repo: repo,
    );
    expect(captured!.lastResumeSessionIds.last, session.sessionId);
    expect(captured!.lastFixedSessionIds.last, isNull);
  });

  test(
    'openSessionTab started session without CLI descriptor uses session-id',
    () async {
      final tmp = await Directory.systemTemp.createTemp('open_sess_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SessionRepository(rootDir: tmp.path);
      final project = await repo.createProject('/wd');
      final session = await repo.createSession(project.projectId);
      await repo.markSessionLaunched(session.sessionId, launchTeam: 'cli-t');

      FakeTerminalSession? captured;
      final cubit = ChatCubit(
        executableResolver: _testExecutable,
        terminalSessionFactory: ({required String executable}) {
          captured = FakeTerminalSession(executable: executable);
          return captured!;
        },
        postFrameScheduler: (c) => c(),
        cliSessionDescriptorExists: (_, __) => false,
      );
      await cubit.loadProjectData(repo);
      final rel = cubit.state.sessions.single;
      final team = TeamConfig(
        id: 'tid',
        name: 'TName',
        members: const [
          TeamMemberConfig(id: 'lid', name: 'team-lead'),
        ],
      );
      cubit.openSessionTab(
        rel,
        team: team,
        member: team.members.first,
        repo: repo,
      );
      expect(captured!.lastResumeSessionIds.last, isNull);
      expect(captured!.lastFixedSessionIds.last, session.sessionId);
    },
  );

  test('openSessionTab passes session additionalDirectories to connect', () async {
    final tmp = await Directory.systemTemp.createTemp('open_sess_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);
    final project = await repo.createProject('/root', additionalPaths: const ['/extra']);
    final session = await repo.createSession(project.projectId);
    FakeTerminalSession? captured;
    final cubit = ChatCubit(
      executableResolver: _testExecutable,
      terminalSessionFactory: ({required String executable}) {
        captured = FakeTerminalSession(executable: executable);
        return captured!;
      },
      postFrameScheduler: (c) => c(),
    );
    await cubit.loadProjectData(repo);
    final rel = cubit.state.sessions.single;
    final team = TeamConfig(
      id: 'tid',
      name: 'TName',
      members: const [
        TeamMemberConfig(id: 'lid', name: 'team-lead'),
      ],
    );
    cubit.openSessionTab(
      rel,
      team: team,
      member: team.members.first,
      repo: repo,
    );
    expect(captured!.lastAdditionalDirectoriesLists.last, ['/extra']);
  });

  test('llm config cubit manages providers and models', () {
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
    expect(cubit.state.config.models.length, 1);

    cubit.deleteProvider('new');
    expect(cubit.state.config.providers.length, 1);
  });
}
