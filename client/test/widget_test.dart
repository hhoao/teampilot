import 'package:flashskyai_client/cubits/chat_cubit.dart';
import 'package:flashskyai_client/cubits/config_cubit.dart';
import 'package:flashskyai_client/cubits/layout_cubit.dart';
import 'package:flashskyai_client/cubits/llm_config_cubit.dart';
import 'package:flashskyai_client/cubits/team_cubit.dart';
import 'package:flashskyai_client/main.dart';
import 'package:flashskyai_client/models/layout_preferences.dart';
import 'package:flashskyai_client/models/llm_config.dart';
import 'package:flashskyai_client/models/team_config.dart';
import 'package:flashskyai_client/repositories/layout_repository.dart';
import 'package:flashskyai_client/repositories/team_repository.dart';
import 'package:flashskyai_client/utils/app_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget buildTestApp({
  required TeamCubit teamCubit,
  LayoutCubit? layoutCubit,
  LlmConfigCubit? llmConfigCubit,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider.value(value: teamCubit),
      BlocProvider(create: (_) => ChatCubit()),
      BlocProvider(create: (_) => ConfigCubit()),
      BlocProvider.value(
        value: llmConfigCubit ?? LlmConfigCubit(),
      ),
      BlocProvider.value(
        value: layoutCubit ?? LayoutCubit(),
      ),
    ],
    child: const FlashskyAiClientApp(),
  );
}

Future<void> pumpDesktopApp(
  WidgetTester tester,
  TeamCubit teamCubit, {
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders chat workbench shell on initial route', (tester) async {
    final teamCubit = await createTeamCubit();
    await pumpDesktopApp(tester, teamCubit);

    expect(find.byKey(AppKeys.contextSidebar), findsOneWidget);
    expect(find.byKey(AppKeys.chatWorkspace), findsOneWidget);
    expect(find.byKey(AppKeys.rightToolsPanel), findsOneWidget);
    expect(find.byKey(AppKeys.membersPanel), findsOneWidget);
    expect(find.byKey(AppKeys.fileTreePanel), findsOneWidget);
    expect(find.text('Default Team'), findsWidgets);
    expect(find.text('Team Sessions'), findsOneWidget);
    expect(find.text('team-lead'), findsWidgets);
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

    cubit.addProvider(const LlmProviderConfig(
      name: 'new',
      type: 'account',
      providerType: '',
    ));
    expect(cubit.state.config.providers.length, 2);

    cubit.addModel(const LlmModelConfig(
      id: 'm1',
      name: 'Model 1',
      provider: 'test',
      model: 'gpt-4',
      enabled: true,
    ));
    expect(cubit.state.config.models.length, 1);

    cubit.deleteProvider('new');
    expect(cubit.state.config.providers.length, 1);
  });
}
