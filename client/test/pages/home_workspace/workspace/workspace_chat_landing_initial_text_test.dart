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
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/commands/command_bus.dart';
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
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets(
    'initialText fills compose field once and survives draft reload',
    (tester) async {
      const seed = 'Selected context\n\n';
      final workspace = Workspace(workspaceId: 'workspace-1', createdAt: 1);
      final chatCubit = _MockChatCubit();
      final appProviderCubit = _MockAppProviderCubit();
      final cliPresetsCubit = _MockCliPresetsCubit();
      final launchProfileCubit = _MockLaunchProfileCubit();
      final pluginCubit = _MockPluginCubit();
      final sessionPreferencesCubit = _MockSessionPreferencesCubit();
      final skillCubit = _MockSkillCubit();
      final worktreeCubit = _MockWorktreeCubit();

      _stubCubit(chatCubit, ChatState(workspaces: [workspace]));

      _stubCubit(appProviderCubit, const AppProviderState());
      _stubCubit(cliPresetsCubit, const CliPresetsState());
      _stubCubit(launchProfileCubit, const LaunchProfileState());
      _stubCubit(pluginCubit, const PluginState());
      _stubCubit(sessionPreferencesCubit, SessionPreferencesState());
      _stubCubit(skillCubit, const SkillState());
      _stubCubit(worktreeCubit, const WorktreeState());
      when(() => worktreeCubit.worktreesForProject(any())).thenReturn(const []);

      Widget landing(String initialText) {
        final theme = buildDarkTheme();
        return MultiRepositoryProvider(
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

      await tester.pumpWidget(landing(seed));
      await tester.pumpAndSettle();

      TextField field() =>
          tester.widget<TextField>(find.byType(TextField).first);
      expect(field().controller!.text, seed);
      expect(field().controller!.selection.baseOffset, seed.length);

      await tester.pumpWidget(landing('replacement'));
      await tester.pump();

      expect(field().controller!.text, seed);
    },
  );
}
