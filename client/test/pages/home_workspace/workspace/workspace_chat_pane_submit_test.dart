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
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/cubits/session/session_phase.dart';
import 'package:teampilot/cubits/session/session_pod.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_pane.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/compose/compose_draft_cache.dart';
import 'package:teampilot/services/compose/compose_draft_store.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../../support/in_memory_filesystem.dart';
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

class _LandingDrafts {
  _LandingDrafts._(this.store, this.cache);

  factory _LandingDrafts() {
    final store = ComposeDraftStore(
      fs: InMemoryFilesystem(),
      rootPath: '/teampilot',
    );
    return _LandingDrafts._(store, ComposeDraftCache(persistentStore: store));
  }

  final ComposeDraftStore store;
  final ComposeDraftCache cache;

  Future<void> seed(String workspaceId, String text) async {
    cache.setLandingDraft(workspaceId, text);
    await store.saveLanding(workspaceId, text);
  }

  Future<void> clear(String workspaceId) async {
    await cache.clearLandingPersistent(workspaceId);
    cache.clearLandingDraft(workspaceId);
  }
}

void main() {
  setUp(() {
    setUpTestAppStorage();
    composeDraftCache.clear();
  });
  tearDown(tearDownTestAppStorage);

  testWidgets(
    'landing stays mounted with scoped progress while the active pod is launching',
    (tester) async {
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

      // Active session is launching → the pane must NOT swap to a full-pane
      // loading view; the landing stays mounted with scoped progress.
      when(() => chatCubit.activePod).thenReturn(
        const SessionPodState(
          sessionId: 'new-session',
          workspaceId: 'workspace-1',
          phase: SessionPhase.connecting,
        ),
      );

      final theme = buildDarkTheme();
      final workbenchCubit = WorkbenchCubit();
      addTearDown(workbenchCubit.close);
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
              BlocProvider<WorkbenchCubit>.value(value: workbenchCubit),
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
                    body: WorkspaceChatPane(workspace: workspace),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The landing is mounted (not replaced by a full-pane loading view) and
      // it reports the scoped submitting flag.
      expect(find.byType(WorkspaceChatLanding), findsOneWidget);
      final landing = tester.widget<WorkspaceChatLanding>(
        find.byType(WorkspaceChatLanding),
      );
      expect(landing.isSubmitting, isTrue);
    },
  );

  testWidgets('failed delivery retains landing drafts', (tester) async {
    const workspaceId = 'workspace-1';
    const draft = 'retry this message';
    final drafts = _LandingDrafts();
    await drafts.seed(workspaceId, draft);

    await tester.pumpWidget(
      _pane(
        submitter:
            (
              _,
              _, {
              required launch,
              required message,
              workingDirectory,
              expertKey,
            }) async => false,
        drafts: drafts,
      ),
    );
    await _settleLanding(tester);

    await _submitLanding(tester, draft);

    expect(drafts.cache.landingDraft(workspaceId), draft);
    expect(await drafts.store.loadLanding(workspaceId), draft);
  });

  testWidgets('successful delivery clears landing drafts', (tester) async {
    const workspaceId = 'workspace-1';
    const draft = 'delivered message';
    final drafts = _LandingDrafts();
    await drafts.seed(workspaceId, draft);

    await tester.pumpWidget(
      _pane(
        submitter:
            (
              _,
              _, {
              required launch,
              required message,
              workingDirectory,
              expertKey,
            }) async => true,
        drafts: drafts,
      ),
    );
    await _settleLanding(tester);

    await _submitLanding(tester, draft);

    expect(drafts.cache.landingDraft(workspaceId), isNull);
    expect(await drafts.store.loadLanding(workspaceId), isNull);
  });

  testWidgets('back control exits the landing to the remembered tab', (
    tester,
  ) async {
    final workbench = WorkbenchCubit();
    workbench.openSession('workspace-1', 'session-1');
    workbench.enterLanding('workspace-1');

    await tester.pumpWidget(
      _pane(
        submitter:
            (
              _,
              _, {
              required launch,
              required message,
              workingDirectory,
              expertKey,
            }) async => false,
        drafts: _LandingDrafts(),
        workbenchCubit: workbench,
      ),
    );
    await _settleLanding(tester);

    expect(
      find.byKey(AppKeys.workspaceChatLandingBackButton),
      findsOneWidget,
    );

    await tester.tap(find.byKey(AppKeys.workspaceChatLandingBackButton));
    await tester.pump();

    expect(
      workbench.centerActiveId('workspace-1'),
      WorkbenchTabId.session('session-1'),
    );
    expect(
      find.byKey(AppKeys.workspaceChatLandingBackButton),
      findsNothing,
    );
  });
}

Future<void> _settleLanding(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _submitLanding(WidgetTester tester, String message) async {
  tester
      .widget<WorkspaceChatLanding>(find.byType(WorkspaceChatLanding))
      .onSubmit(
        message,
        const LandingLaunchContext(
          isPersonal: true,
          workingDirectoryPath: '/workspace',
        ),
      );
  await tester.pump();
  await tester.pump();
}

Widget _pane({
  required dynamic submitter,
  required _LandingDrafts drafts,
  WorkbenchCubit? workbenchCubit,
}) {
  final workspace = Workspace(workspaceId: 'workspace-1', createdAt: 1);
  final chatCubit = _MockChatCubit();
  final appProviderCubit = _MockAppProviderCubit();
  final cliPresetsCubit = _MockCliPresetsCubit();
  final launchProfileCubit = _MockLaunchProfileCubit();
  final pluginCubit = _MockPluginCubit();
  final sessionPreferencesCubit = _MockSessionPreferencesCubit();
  final skillCubit = _MockSkillCubit();
  final worktreeCubit = _MockWorktreeCubit();
  final workbench = workbenchCubit ?? WorkbenchCubit();
  addTearDown(workbench.close);
  _stubCubit(chatCubit, ChatState(workspaces: [workspace]));
  _stubCubit(appProviderCubit, const AppProviderState());
  _stubCubit(cliPresetsCubit, const CliPresetsState());
  _stubCubit(launchProfileCubit, const LaunchProfileState());
  _stubCubit(pluginCubit, const PluginState());
  _stubCubit(sessionPreferencesCubit, SessionPreferencesState());
  _stubCubit(skillCubit, const SkillState());
  _stubCubit(worktreeCubit, const WorktreeState());
  when(() => worktreeCubit.worktreesForProject(any())).thenReturn(const []);
  when(() => chatCubit.activePod).thenReturn(null);
  final theme = buildDarkTheme();
  return MultiRepositoryProvider(
    providers: [RepositoryProvider<CommandBus>(create: (_) => CommandBus())],
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
        BlocProvider<WorkbenchCubit>.value(value: workbench),
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
              body: WorkspaceChatPane(
                workspace: workspace,
                submitter: submitter,
                landingDraftPersister: (_, _) async {},
                landingDraftCleaner: drafts.clear,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
