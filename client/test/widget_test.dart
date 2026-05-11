import 'dart:io';

import 'package:flashskyai_client/cubits/chat_cubit.dart';
import 'package:flashskyai_client/cubits/config_cubit.dart';
import 'package:flashskyai_client/cubits/layout_cubit.dart';
import 'package:flashskyai_client/cubits/llm_config_cubit.dart';
import 'package:flashskyai_client/cubits/team_cubit.dart';
import 'package:flashskyai_client/main.dart';
import 'package:flashskyai_client/models/layout_preferences.dart';
import 'package:flashskyai_client/models/llm_config.dart';
import 'package:flashskyai_client/models/session.dart';
import 'package:flashskyai_client/models/team_config.dart';
import 'package:flashskyai_client/repositories/layout_repository.dart';
import 'package:flashskyai_client/repositories/team_repository.dart';
import 'package:flashskyai_client/services/terminal_session.dart';
import 'package:flashskyai_client/theme/app_theme.dart';
import 'package:flashskyai_client/utils/app_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget buildTestApp({
  required TeamCubit teamCubit,
  ChatCubit? chatCubit,
  LayoutCubit? layoutCubit,
  LlmConfigCubit? llmConfigCubit,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider.value(value: teamCubit),
      BlocProvider.value(value: chatCubit ?? ChatCubit()),
      BlocProvider(create: (_) => ConfigCubit()),
      BlocProvider.value(value: llmConfigCubit ?? LlmConfigCubit()),
      BlocProvider.value(value: layoutCubit ?? LayoutCubit()),
    ],
    child: const FlashskyAiClientApp(),
  );
}

Future<void> pumpDesktopApp(
  WidgetTester tester,
  TeamCubit teamCubit, {
  ChatCubit? chatCubit,
  LayoutCubit? layoutCubit,
  LlmConfigCubit? llmConfigCubit,
}) async {
  tester.view.physicalSize = const Size(1200, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    buildTestApp(
      teamCubit: teamCubit,
      chatCubit: chatCubit,
      layoutCubit: layoutCubit,
      llmConfigCubit: llmConfigCubit,
    ),
  );
  await tester.pumpAndSettle();
}

Future<TeamCubit> createTeamCubit({TeamLauncher? launcher}) async {
  final repository = TeamRepository(await SharedPreferences.getInstance());
  final cubit = TeamCubit(
    repository: repository,
    launcher: launcher ?? (_, __) async {},
    currentDirectoryProvider: () => '/work/current',
  );
  await cubit.load();
  return cubit;
}

class FakeTerminalSession extends TerminalSession {
  var _running = false;
  final connectedMembers = <String>[];
  final resumedSessions = <String>[];

  @override
  bool get isRunning => _running;

  @override
  void connect(TeamConfig team, TeamMemberConfig member) {
    _running = true;
    connectedMembers.add(member.id);
  }

  @override
  void connectResume(String sessionId) {
    _running = true;
    resumedSessions.add(sessionId);
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
        terminalSessionFactory: FakeTerminalSession.new,
        postFrameScheduler: (callback) => callback(),
      );

  void seedSessions(List<FlashskySession> sessions) {
    emit(state.copyWith(sessions: sessions));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders chat workbench shell on initial route', (tester) async {
    final teamCubit = await createTeamCubit();
    final chatCubit = ChatCubit(
      terminalSessionFactory: FakeTerminalSession.new,
      postFrameScheduler: (callback) => callback(),
    );
    await pumpDesktopApp(tester, teamCubit, chatCubit: chatCubit);

    expect(find.byKey(AppKeys.contextSidebar), findsOneWidget);
    expect(find.byKey(AppKeys.chatWorkspace), findsOneWidget);
    expect(find.byKey(AppKeys.rightToolsPanel), findsOneWidget);
    expect(find.byKey(AppKeys.membersPanel), findsOneWidget);
    expect(find.byKey(AppKeys.fileTreePanel), findsOneWidget);
    expect(find.text('Default Team'), findsWidgets);
    expect(find.text('Team Sessions'), findsOneWidget);
    expect(find.text('team-lead'), findsWidgets);
    expect(chatCubit.state.tabs.length, 1);
    expect(chatCubit.state.tabs.single.id, 'local-default');

    await tester.tap(find.byKey(AppKeys.memberRow('team-lead')));
    await tester.pump();

    expect(chatCubit.state.tabs.length, 1);
    expect(chatCubit.state.tabs.single.id, 'local-default');
    expect(chatCubit.isMemberRunning('team-lead'), isTrue);
  });

  testWidgets('renders settings shell with title bar and icon navigation', (
    tester,
  ) async {
    final teamCubit = await createTeamCubit();
    await pumpDesktopApp(tester, teamCubit);

    await tester.tap(find.byKey(AppKeys.sidebarSettingsButton));
    await tester.pumpAndSettle();

    expect(
      find.text('Manage FlashskyAI team and model settings.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.groups_2_outlined), findsOneWidget);
    expect(find.byIcon(Icons.memory_outlined), findsOneWidget);
  });

  testWidgets('settings pages use the global component theme', (tester) async {
    final teamCubit = await createTeamCubit();
    await pumpDesktopApp(tester, teamCubit);

    await tester.tap(find.byKey(AppKeys.sidebarSettingsButton));
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    final providerList = tester.widget<Container>(
      find.byKey(AppKeys.llmProviderList),
    );
    final decoration = providerList.decoration! as BoxDecoration;
    expect(decoration.color, appColors.cardBackground);
  });

  testWidgets('opening a sidebar session starts team-lead member shell', (
    tester,
  ) async {
    final teamCubit = await createTeamCubit();
    final chatCubit = TestChatCubit();
    chatCubit.seedSessions(const [
      FlashskySession(
        sessionId: 'session-1',
        cwd: '/work/current',
        kind: 'interactive',
        display: 'Session One',
      ),
    ]);

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
    final repository = TeamRepository(await SharedPreferences.getInstance());
    final cubit = TeamCubit(
      repository: repository,
      currentDirectoryProvider: () => '/work/current',
    );
    await cubit.load();

    expect(cubit.state.selectedTeam?.name, 'Default Team');
    expect(cubit.state.teams.length, 1);

    cubit.selectTeam('default');
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
    expect(cubit.state.section, ConfigSection.team);

    cubit.selectSection(ConfigSection.members);
    expect(cubit.state.section, ConfigSection.members);

    cubit.selectSection(ConfigSection.layout);
    expect(cubit.state.section, ConfigSection.layout);
  });

  test('chat cubit manages tabs and selection', () {
    final cubit = ChatCubit();
    expect(cubit.state.tabs, isEmpty);
    expect(cubit.state.selectedMemberId, isEmpty);

    final team = TeamConfig(
      id: 'test-team',
      name: 'Test',
      workingDirectory: '/tmp',
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

  test('chat cubit opens member shells inside one session tab', () {
    final cubit = ChatCubit(
      terminalSessionFactory: FakeTerminalSession.new,
      postFrameScheduler: (callback) => callback(),
    );
    final team = TeamConfig(
      id: 'test-team',
      name: 'Test',
      workingDirectory: '/tmp',
      members: const [
        TeamMemberConfig(id: 'lead', name: 'team-lead'),
        TeamMemberConfig(id: 'dev', name: 'developer'),
      ],
    );

    cubit.openMemberTab(team, team.members[0]);
    cubit.openMemberTab(team, team.members[1]);

    expect(cubit.state.tabs.length, 1);
    expect(cubit.state.tabs.single.id, 'local-test-team');
    expect(cubit.state.selectedMemberId, 'dev');
    expect(cubit.isMemberRunning('lead'), isTrue);
    expect(cubit.isMemberRunning('dev'), isTrue);
  });

  test(
    'chat cubit keeps persisted session tabs separate from member selection',
    () {
      final cubit = ChatCubit(
        terminalSessionFactory: FakeTerminalSession.new,
        postFrameScheduler: (callback) => callback(),
      );
      const session = FlashskySession(
        sessionId: 'session-1',
        cwd: '/tmp',
        kind: 'interactive',
        display: 'Session One',
      );
      final team = TeamConfig(
        id: 'test-team',
        name: 'Test',
        workingDirectory: '/tmp',
        members: const [
          TeamMemberConfig(id: 'lead', name: 'team-lead'),
          TeamMemberConfig(id: 'dev', name: 'developer'),
        ],
      );

      cubit.openSessionTab(session);
      cubit.openMemberTab(team, team.members[0]);
      cubit.openMemberTab(team, team.members[1]);

      expect(cubit.state.tabs.length, 1);
      expect(cubit.state.tabs.single.id, 'session-1');
      expect(cubit.state.activeSessionId, 'session-1');
      expect(cubit.state.selectedMemberId, 'dev');
      expect(cubit.isMemberRunning('lead'), isTrue);
      expect(cubit.isMemberRunning('dev'), isTrue);
    },
  );

  test('llm config cubit manages providers and models', () {
    final cubit = LlmConfigCubit(
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
