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
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/models/session_preferences.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/workspace/unbound_compose_body.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_draft_cache.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

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

CliPreset _preset(String id, CliTool cli) => CliPreset(
  id: id,
  name: id,
  cli: cli,
  provider: '',
  model: '',
  createdAt: 1,
  updatedAt: 1,
);

void main() {
  setUp(() {
    setUpTestAppStorage();
    composeDraftCache.clear();
  });
  tearDown(tearDownTestAppStorage);

  Future<_MockSessionPreferencesCubit> pumpCompose(
    WidgetTester tester, {
    required CliTool cli,
    required bool preferenceDefault,
    required List<LandingLaunchContext> submitted,
  }) async {
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
    _stubCubit(
      cliPresetsCubit,
      CliPresetsState(presets: [_preset('preset-1', cli)]),
    );
    _stubCubit(launchProfileCubit, const LaunchProfileState());
    _stubCubit(pluginCubit, const PluginState());
    _stubCubit(
      sessionPreferencesCubit,
      SessionPreferencesState(
        preferences: SessionPreferences(
          claudePersonalAcpDefault: preferenceDefault,
        ),
      ),
    );
    _stubCubit(skillCubit, const SkillState());
    _stubCubit(worktreeCubit, const WorktreeState());
    when(() => worktreeCubit.worktreesForProject(any())).thenReturn(const []);
    when(() => chatCubit.remoteCliReadiness).thenReturn(null);

    final theme = buildDarkTheme();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<CommandBus>(create: (_) => CommandBus()),
          RepositoryProvider<HomeStorage>.value(value: testHomeStorage),
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
                data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1),
                child: Scaffold(
                  body: UnboundComposeBody(
                    workspace: workspace,
                    onSubmit: (_, draft) => submitted.add(draft),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Landing draft hydration seeds the first preset asynchronously.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump();
    return sessionPreferencesCubit;
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, 'hello');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }

  testWidgets('Claude preset shows the compose ACP switch', (tester) async {
    await pumpCompose(
      tester,
      cli: CliTool.claude,
      preferenceDefault: false,
      submitted: [],
    );
    expect(find.byKey(AppKeys.claudeAcpLaunchSwitch), findsOneWidget);
  });

  testWidgets('non-Claude preset hides the compose ACP switch', (tester) async {
    await pumpCompose(
      tester,
      cli: CliTool.codex,
      preferenceDefault: true,
      submitted: [],
    );
    expect(find.byKey(AppKeys.claudeAcpLaunchSwitch), findsNothing);
  });

  testWidgets('submit carries acp=false by default', (tester) async {
    final submitted = <LandingLaunchContext>[];
    await pumpCompose(
      tester,
      cli: CliTool.claude,
      preferenceDefault: false,
      submitted: submitted,
    );
    await submit(tester);
    expect(submitted, hasLength(1));
    expect(submitted.single.acp, isFalse);
  });

  testWidgets('compose switch initializes from the settings default', (
    tester,
  ) async {
    final submitted = <LandingLaunchContext>[];
    await pumpCompose(
      tester,
      cli: CliTool.claude,
      preferenceDefault: true,
      submitted: submitted,
    );
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(AppKeys.claudeAcpLaunchSwitch))
          .value,
      isTrue,
    );
    await submit(tester);
    expect(submitted.single.acp, isTrue);
  });

  testWidgets('flipping the compose switch sets acp without writing the pref', (
    tester,
  ) async {
    final submitted = <LandingLaunchContext>[];
    final prefs = await pumpCompose(
      tester,
      cli: CliTool.claude,
      preferenceDefault: false,
      submitted: submitted,
    );
    await tester.tap(find.byKey(AppKeys.claudeAcpLaunchSwitch));
    await tester.pump();
    await submit(tester);
    expect(submitted.single.acp, isTrue);
    verifyNever(() => prefs.setClaudePersonalAcpDefault(any()));
  });
}
