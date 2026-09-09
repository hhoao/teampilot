import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/compose/compose_draft_cache.dart';
import 'package:teampilot/services/home_workspace/landing_prefs_store.dart';
import 'package:teampilot/theme/app_theme.dart';

import '../../../support/post_frame_test_harness.dart';

class _MockChatCubit extends Mock implements ChatCubit {}

class _MockAppProviderCubit extends Mock implements AppProviderCubit {}

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
  tearDown(() {
    composeDraftCache.clear();
    tearDownTestAppStorage();
  });

  testWidgets(
    'generate-launch mode: send button stays clickable without a concrete team',
    (tester) async {
      final workspace = Workspace(workspaceId: 'workspace-gen', createdAt: 1);
      // Seed the landing draft into generation mode (team mode + generate).
      // No team is selected — generation builds the team instead of picking one.
      // Real file IO must run outside the FakeAsync zone.
      await tester.runAsync(
        () => LandingPrefsStore().save(
          workspace.workspaceId,
          const LandingPrefs(isPersonal: false, generateLaunch: true),
        ),
      );

      final chatCubit = _MockChatCubit();
      final appProviderCubit = _MockAppProviderCubit();
      final cliPresetsCubit = _MockCliPresetsCubit();
      final launchProfileCubit = _MockLaunchProfileCubit();
      final pluginCubit = _MockPluginCubit();
      final sessionPreferencesCubit = _MockSessionPreferencesCubit();
      final skillCubit = _MockSkillCubit();
      final worktreeCubit = _MockWorktreeCubit();

      _stubCubit(chatCubit, ChatState(workspaces: [workspace]));
      when(() => chatCubit.remoteCliReadiness).thenReturn(null);

      _stubCubit(appProviderCubit, const AppProviderState());
      _stubCubit(cliPresetsCubit, const CliPresetsState());
      _stubCubit(launchProfileCubit, const LaunchProfileState());
      _stubCubit(pluginCubit, const PluginState());
      _stubCubit(sessionPreferencesCubit, SessionPreferencesState());
      _stubCubit(skillCubit, const SkillState());
      _stubCubit(worktreeCubit, const WorktreeState());
      when(() => worktreeCubit.worktreesForProject(any())).thenReturn(const []);

      final submits = <(String, LandingLaunchContext)>[];

      final theme = buildDarkTheme();
      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<CommandBus>(create: (_) => CommandBus()),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ChatCubit>.value(value: chatCubit),
              BlocProvider<AppProviderCubit>.value(value: appProviderCubit),
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
                      onSubmit: (message, draft) =>
                          submits.add((message, draft)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // Bounded pumps plus runAsync flushes: the draft load runs unawaited
      // real IO inside the widget state and must complete before asserting.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump();
      }

      // Generation mode restored from the draft.
      expect(find.text('Generate and launch'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).first,
        'build a team for this repo',
      );
      await tester.pump();

      // The send button must be active without a concrete team selected.
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump();
      }

      expect(submits, hasLength(1));
      expect(submits.single.$1, 'build a team for this repo');
      expect(submits.single.$2.generateLaunch, isTrue);
      expect(submits.single.$2.isPersonal, isFalse);
    },
  );
}
