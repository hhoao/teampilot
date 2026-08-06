import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/compose/compose_draft_cache.dart';
import 'package:teampilot/theme/app_theme.dart';

import '../../../support/post_frame_test_harness.dart';

class _MockChatCubit extends Mock implements ChatCubit {}

class _MockCliPresetsCubit extends Mock implements CliPresetsCubit {}

class _MockLaunchProfileCubit extends Mock implements LaunchProfileCubit {}

class _MockPluginCubit extends Mock implements PluginCubit {}

class _MockSessionPreferencesCubit extends Mock
    implements SessionPreferencesCubit {}

class _MockSkillCubit extends Mock implements SkillCubit {}

class _MockWorktreeCubit extends Mock implements WorktreeCubit {}

void _stubCubit<TState>(Cubit<TState> cubit, TState state) {
  when(() => cubit.state).thenReturn(state);
  when(() => cubit.stream).thenAnswer((_) => Stream<TState>.empty());
}

void main() {
  setUp(() {
    setUpTestAppStorage();
    composeDraftCache.clear();
  });
  tearDown(tearDownTestAppStorage);

  testWidgets('restores the cached landing draft on mount', (tester) async {
    composeDraftCache.setLandingDraft('workspace-1', 'my draft');
    await tester.pumpWidget(_landing(initialText: null));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'my draft');
    expect(field.controller!.selection.baseOffset, 'my draft'.length);
  });

  testWidgets('does not restore the cache when initialText is provided',
      (tester) async {
    composeDraftCache.setLandingDraft('workspace-1', 'cached');
    await tester.pumpWidget(_landing(initialText: 'prefill'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'prefill');
    // The pre-seeded cache entry is untouched by Ask AI-style mounts.
    expect(composeDraftCache.landingDraft('workspace-1'), 'cached');
  });

  testWidgets('typing writes the draft into the cache', (tester) async {
    await tester.pumpWidget(_landing(initialText: null));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'typed message');
    await tester.pump();

    expect(composeDraftCache.landingDraft('workspace-1'), 'typed message');
  });

  testWidgets('clearing the field removes the cached draft', (tester) async {
    composeDraftCache.setLandingDraft('workspace-1', 'old');
    await tester.pumpWidget(_landing(initialText: null));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();

    expect(composeDraftCache.landingDraft('workspace-1'), isNull);
  });

  testWidgets('remounting after unmount restores the typed draft',
      (tester) async {
    await tester.pumpWidget(_landing(initialText: null));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'work in progress');
    await tester.pump();

    // Simulate navigating away and back — host unmounts, then remounts.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_landing(initialText: null));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'work in progress');
  });
}

Widget _landing({required String? initialText}) {
  final workspace = Workspace(workspaceId: 'workspace-1', createdAt: 1);
  final chatCubit = _MockChatCubit();
  final cliPresetsCubit = _MockCliPresetsCubit();
  final launchProfileCubit = _MockLaunchProfileCubit();
  final pluginCubit = _MockPluginCubit();
  final sessionPreferencesCubit = _MockSessionPreferencesCubit();
  final skillCubit = _MockSkillCubit();
  final worktreeCubit = _MockWorktreeCubit();

  _stubCubit(chatCubit, ChatState(workspaces: [workspace]));
  _stubCubit(cliPresetsCubit, const CliPresetsState());
  _stubCubit(launchProfileCubit, const LaunchProfileState());
  _stubCubit(pluginCubit, const PluginState());
  _stubCubit(sessionPreferencesCubit, SessionPreferencesState());
  _stubCubit(skillCubit, const SkillState());
  _stubCubit(worktreeCubit, const WorktreeState());
  when(() => worktreeCubit.worktreesForProject(any())).thenReturn(const []);

  final theme = buildDarkTheme();
  return MultiRepositoryProvider(
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
        BlocProvider<WorktreeCubit>.value(value: worktreeCubit),
      ],
      child: CliToolRegistryScope(
        registry: CliToolRegistry.builtIn(),
        child: MaterialApp(
          theme: theme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TpTheme(
            data: TpThemeData.fromColorScheme(
              theme.colorScheme,
              scale: 1,
            ),
            child: Scaffold(
              body: WorkspaceChatLanding(
                workspace: workspace,
                initialText: initialText,
                onSubmit: (_, _) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
