import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing_compose_card.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_landing_selectors.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/selection_ai/selection_ask_ai.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/post_frame_test_harness.dart';

const _dismissKey = Key('selection-ask-ai-dismiss');

void _expectComposeOnlyAskAiDialog() {
  expect(find.text('Ask AI…'), findsNothing);
  expect(find.byType(TpDialogHeader), findsNothing);
  expect(find.byType(WorkspaceChatLanding), findsOneWidget);
  expect(find.byType(WorkspaceChatLandingComposeCard), findsOneWidget);
  expect(find.byKey(AppKeys.workspaceChatLandingBackButton), findsNothing);
  expect(find.byType(WorkspaceLandingHeaderRow), findsNothing);
}

class _MockChatCubit extends Mock implements ChatCubit {}

class _MockCliPresetsCubit extends Mock implements CliPresetsCubit {}

class _MockLaunchProfileCubit extends Mock implements LaunchProfileCubit {}

class _MockPluginCubit extends Mock implements PluginCubit {}

class _MockSessionPreferencesCubit extends Mock
    implements SessionPreferencesCubit {}

class _MockSkillCubit extends Mock implements SkillCubit {}

void _stubCubit<TState>(Cubit<TState> cubit, TState state) {
  when(() => cubit.state).thenReturn(state);
  when(() => cubit.stream).thenAnswer((_) => Stream<TState>.empty());
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('empty AI context does not open compose dialog', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox();
          },
        ),
      ),
    );

    await SelectionAskAi.openComposeDialog(
      context,
      aiContext: '  ',
      workspace: Workspace(workspaceId: 'workspace-1', createdAt: 1),
      tabScopeId: 'workspace-1',
    );
    await tester.pump();

    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('dialog inherits WorktreeCubit from opener context', (
    tester,
  ) async {
    final workspace = Workspace(
      workspaceId: 'workspace-1',
      createdAt: 1,
      folders: const [WorkspaceFolder(path: '/repo')],
    );
    final chatCubit = _MockChatCubit();
    final cliPresetsCubit = _MockCliPresetsCubit();
    final launchProfileCubit = _MockLaunchProfileCubit();
    final pluginCubit = _MockPluginCubit();
    final sessionPreferencesCubit = _MockSessionPreferencesCubit();
    final skillCubit = _MockSkillCubit();
    final worktreeCubit = WorktreeCubit();
    addTearDown(worktreeCubit.close);

    _stubCubit(chatCubit, ChatState(workspaces: [workspace]));
    final tabStore = ChatTabStore()..setActiveWorkspace(workspace.workspaceId);
    when(() => chatCubit.tabStore).thenReturn(tabStore);
    _stubCubit(cliPresetsCubit, const CliPresetsState());
    _stubCubit(launchProfileCubit, const LaunchProfileState());
    _stubCubit(pluginCubit, const PluginState());
    _stubCubit(sessionPreferencesCubit, SessionPreferencesState());
    _stubCubit(skillCubit, const SkillState());

    final theme = buildDarkTheme();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<CommandBus>(create: (_) => CommandBus()),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ChatCubit>.value(value: chatCubit),
            BlocProvider<CliPresetsCubit>.value(value: cliPresetsCubit),
            BlocProvider<LaunchProfileCubit>.value(value: launchProfileCubit),
            BlocProvider<PluginCubit>.value(value: pluginCubit),
            BlocProvider<SessionPreferencesCubit>.value(
              value: sessionPreferencesCubit,
            ),
            BlocProvider<SkillCubit>.value(value: skillCubit),
          ],
          child: CliToolRegistryScope(
            registry: CliToolRegistry.builtIn(),
            child: MaterialApp(
              theme: theme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: TpTheme(
                data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1),
                child: BlocProvider<WorktreeCubit>.value(
                  value: worktreeCubit,
                  child: Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () => unawaited(
                        SelectionAskAi.openComposeDialog(
                          context,
                          aiContext: 'Selected code',
                          workspace: workspace,
                          tabScopeId: workspace.workspaceId,
                        ),
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    _expectComposeOnlyAskAiDialog();
  });

  testWidgets('Ask AI dialog dismiss control closes the dialog', (
    tester,
  ) async {
    final workspace = Workspace(
      workspaceId: 'workspace-1',
      createdAt: 1,
      folders: const [WorkspaceFolder(path: '/repo')],
    );
    final chatCubit = _MockChatCubit();
    final cliPresetsCubit = _MockCliPresetsCubit();
    final launchProfileCubit = _MockLaunchProfileCubit();
    final pluginCubit = _MockPluginCubit();
    final sessionPreferencesCubit = _MockSessionPreferencesCubit();
    final skillCubit = _MockSkillCubit();
    final worktreeCubit = WorktreeCubit();
    addTearDown(worktreeCubit.close);

    _stubCubit(chatCubit, ChatState(workspaces: [workspace]));
    final tabStore = ChatTabStore()..setActiveWorkspace(workspace.workspaceId);
    when(() => chatCubit.tabStore).thenReturn(tabStore);
    _stubCubit(cliPresetsCubit, const CliPresetsState());
    _stubCubit(launchProfileCubit, const LaunchProfileState());
    _stubCubit(pluginCubit, const PluginState());
    _stubCubit(sessionPreferencesCubit, SessionPreferencesState());
    _stubCubit(skillCubit, const SkillState());

    final theme = buildDarkTheme();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<CommandBus>(create: (_) => CommandBus()),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ChatCubit>.value(value: chatCubit),
            BlocProvider<CliPresetsCubit>.value(value: cliPresetsCubit),
            BlocProvider<LaunchProfileCubit>.value(value: launchProfileCubit),
            BlocProvider<PluginCubit>.value(value: pluginCubit),
            BlocProvider<SessionPreferencesCubit>.value(
              value: sessionPreferencesCubit,
            ),
            BlocProvider<SkillCubit>.value(value: skillCubit),
          ],
          child: CliToolRegistryScope(
            registry: CliToolRegistry.builtIn(),
            child: MaterialApp(
              theme: theme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: TpTheme(
                data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1),
                child: BlocProvider<WorktreeCubit>.value(
                  value: worktreeCubit,
                  child: Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () => unawaited(
                        SelectionAskAi.openComposeDialog(
                          context,
                          aiContext: 'Selected code',
                          workspace: workspace,
                          tabScopeId: workspace.workspaceId,
                        ),
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(WorkspaceChatLanding), findsOneWidget);

    await tester.tap(find.byKey(_dismissKey));
    await tester.pumpAndSettle();

    expect(find.byType(WorkspaceChatLanding), findsNothing);
  });

  testWidgets('dialog builds under MaterialApp.router without route lookup '
      'errors', (tester) async {
    final workspace = Workspace(
      workspaceId: 'workspace-1',
      createdAt: 1,
      folders: const [WorkspaceFolder(path: '/repo')],
    );
    final chatCubit = _MockChatCubit();
    final cliPresetsCubit = _MockCliPresetsCubit();
    final launchProfileCubit = _MockLaunchProfileCubit();
    final pluginCubit = _MockPluginCubit();
    final sessionPreferencesCubit = _MockSessionPreferencesCubit();
    final skillCubit = _MockSkillCubit();
    final worktreeCubit = WorktreeCubit();
    addTearDown(worktreeCubit.close);

    _stubCubit(chatCubit, ChatState(workspaces: [workspace]));
    final tabStore = ChatTabStore()..setActiveWorkspace(workspace.workspaceId);
    when(() => chatCubit.tabStore).thenReturn(tabStore);
    _stubCubit(cliPresetsCubit, const CliPresetsState());
    _stubCubit(launchProfileCubit, const LaunchProfileState());
    _stubCubit(pluginCubit, const PluginState());
    _stubCubit(sessionPreferencesCubit, SessionPreferencesState());
    _stubCubit(skillCubit, const SkillState());

    final theme = buildDarkTheme();
    final router = GoRouter(
      initialLocation: '/home-v2/workspace/workspace-1?member=teampilot/expert',
      routes: [
        GoRoute(
          path: '/home-v2/workspace/:workspaceId',
          builder: (context, state) => TpTheme(
            data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1),
            child: BlocProvider<WorktreeCubit>.value(
              value: worktreeCubit,
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => unawaited(
                    SelectionAskAi.openComposeDialog(
                      context,
                      aiContext: 'Selected code',
                      workspace: workspace,
                      tabScopeId: workspace.workspaceId,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<CommandBus>(create: (_) => CommandBus()),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ChatCubit>.value(value: chatCubit),
            BlocProvider<CliPresetsCubit>.value(value: cliPresetsCubit),
            BlocProvider<LaunchProfileCubit>.value(value: launchProfileCubit),
            BlocProvider<PluginCubit>.value(value: pluginCubit),
            BlocProvider<SessionPreferencesCubit>.value(
              value: sessionPreferencesCubit,
            ),
            BlocProvider<SkillCubit>.value(value: skillCubit),
          ],
          child: CliToolRegistryScope(
            registry: CliToolRegistry.builtIn(),
            child: MaterialApp.router(
              theme: theme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    _expectComposeOnlyAskAiDialog();
  });
}
