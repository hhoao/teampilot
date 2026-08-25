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
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_project_config.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing.dart';
import 'package:teampilot/repositories/workspace_project_config_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/compose/compose_slash_catalog.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/utils/workspace/landing_draft_resolver.dart';
import 'package:teampilot/widgets/compose/compose_trigger_field.dart';

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

const _skill = Skill(
  id: 'workflow-skill',
  name: 'Workflow Skill',
  description: '',
  directory: 'workflow-skill',
  installedAt: 0,
  updatedAt: 0,
);

const _plugin = Plugin(
  id: 'review-plugin',
  name: 'Review Plugin',
  description: '',
  version: '1.0',
  directory: 'review-plugin',
  installedAt: 0,
  updatedAt: 0,
  capabilities: PluginCapabilities(commands: [PluginCommand(name: 'review')]),
);

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  Future<void> pumpLanding(
    WidgetTester tester, {
    required LandingLaunchContext draft,
  }) async {
    final workspace = Workspace(workspaceId: 'workspace-1', createdAt: 1);
    await tester.runAsync(() async {
      await persistLandingDraft(workspace.workspaceId, draft);
      await WorkspaceProjectConfigRepository().save(
        workspace.workspaceId,
        const WorkspaceProjectConfig(
          bundle: ConfigBundle(
            skillIds: ['workflow-skill'],
            pluginIds: ['review-plugin'],
          ),
        ),
      );
    });

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
    _stubCubit(pluginCubit, const PluginState(installed: [_plugin]));
    _stubCubit(sessionPreferencesCubit, SessionPreferencesState());
    _stubCubit(skillCubit, const SkillState(installed: [_skill]));
    _stubCubit(worktreeCubit, const WorktreeState());
    when(() => worktreeCubit.worktreesForProject(any())).thenReturn(const []);

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
                  body: WorkspaceChatLanding(
                    workspace: workspace,
                    onSubmit: (_, _) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
  }

  List<ComposeSlashCandidate> candidatesFor(ComposeTriggerField field) =>
      buildComposeSlashCandidates(
        skills: field.skills,
        plugins: field.plugins,
        enabledBundle: field.slashBundle,
        query: '',
        syntax: field.skillSyntax,
        nativeCommands: field.nativeCommands,
      );

  testWidgets(
    'landing resolves Codex native commands with enabled skills and plugins',
    (tester) async {
      await pumpLanding(
        tester,
        draft: const LandingLaunchContext(isPersonal: true, cli: CliTool.codex),
      );

      final field = tester.widget<ComposeTriggerField>(
        find.byType(ComposeTriggerField),
      );
      expect(field.nativeCommands.map((command) => command.name), [
        'goal',
        'compact',
        'help',
      ]);

      expect(candidatesFor(field).map((candidate) => candidate.insertText), [
        r'$workflow-skill',
        '/compact ',
        '/goal ',
        '/help',
        '/review',
      ]);
    },
  );

  testWidgets(
    'landing without an effective CLI keeps enabled catalog items but no native suggestions',
    (tester) async {
      await pumpLanding(
        tester,
        draft: const LandingLaunchContext(isPersonal: true),
      );

      final field = tester.widget<ComposeTriggerField>(
        find.byType(ComposeTriggerField),
      );
      expect(field.nativeCommands, isEmpty);

      expect(candidatesFor(field).map((candidate) => candidate.insertText), [
        '/workflow-skill',
        '/review',
      ]);
    },
  );
}
