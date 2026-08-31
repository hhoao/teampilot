import 'package:ai_message_core/ai_message_core.dart'
    show ExternalStoreAiThreadRuntime;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/ai_history_cubit.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/expert_hub_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/models/workspace_project_config.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/pages/chat/session_chat_view.dart';
import 'package:teampilot/repositories/workspace_project_config_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/compose/compose_draft_cache.dart';
import 'package:teampilot/services/compose/compose_slash_catalog.dart';
import 'package:teampilot/services/follow_up/follow_up_queue.dart';
import 'package:teampilot/services/session/failed_message_store.dart';
import 'package:teampilot/services/session/history_awaiting_working_sync.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/widgets/compose/compose_trigger_field.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

class _MockChatCubit extends Mock implements ChatCubit {}

class _MockAiHistoryCubit extends Mock implements AiHistoryCubit {}

class _MockAiHistorySeat extends Mock implements AiHistorySeat {}

class _MockCliPresetsCubit extends Mock implements CliPresetsCubit {}

class _MockLaunchProfileCubit extends Mock implements LaunchProfileCubit {}

class _MockPluginCubit extends Mock implements PluginCubit {}

class _MockSkillCubit extends Mock implements SkillCubit {}

class _MockSessionPreferencesCubit extends Mock
    implements SessionPreferencesCubit {}

class _MockAppProviderCubit extends Mock implements AppProviderCubit {}

class _MockExpertHubCubit extends Mock implements ExpertHubCubit {}

class _MockAgentAttentionCubit extends Mock implements AgentAttentionCubit {}

class _MockEditorCubit extends Mock implements EditorCubit {}

class _MockWorktreeCubit extends Mock implements WorktreeCubit {}

class _MockMemberPresenceCubit extends Mock implements MemberPresenceCubit {}

class _MockLayoutCubit extends Mock implements LayoutCubit {}

class _MockSessionLifecycleService extends Mock
    implements SessionLifecycleService {}

class _FakeFailedMessageStore extends Fake implements FailedMessageStore {}

void _stubCubit<TState>(Cubit<TState> cubit, TState state) {
  when(() => cubit.state).thenReturn(state);
  when(() => cubit.stream).thenAnswer((_) => Stream<TState>.empty());
}

/// Regression: the history review compose slash menu must show workspace-level
/// skills from `project-config.json` just like the landing compose does
/// (session_chat_compose_section used to pass an empty workspace bundle).
void main() {
  late _MockAiHistorySeat seat;

  setUpAll(() {
    final fbWorkspace = Workspace(
      workspaceId: 'ws-fb',
      createdAt: 0,
    );
    final fbSession = AppSession(
      sessionId: 'fb',
      workspaceId: 'ws-fb',
      folders: const [],
      createdAt: 0,
    );
    registerFallbackValue(fbSession);
    registerFallbackValue(
      WorkspaceLaunchContext(session: fbSession, workspace: fbWorkspace),
    );
    registerFallbackValue(
      const TeamProfile(
        id: 'fb',
        name: 'fb',
        teamMode: TeamMode.native,
        members: [],
      ),
    );
    registerFallbackValue(_FakeFailedMessageStore());
  });

  setUp(() {
    setUpTestAppStorage();
    composeDraftCache.clear();

    seat = _MockAiHistorySeat();
    _stubCubit(seat, const AiHistoryState());
    when(() => seat.subagentAttachments).thenReturn(const {});
    when(() => seat.runtime).thenReturn(ExternalStoreAiThreadRuntime());
    when(() => seat.loadedMessages).thenReturn(const []);
    when(() => seat.pendingDeliveryStatuses).thenReturn(const {});
    when(() => seat.hasOptimisticPending).thenReturn(false);
    when(
      () => seat.hydratePendingUsers(
        store: any(named: 'store'),
        workspaceId: any(named: 'workspaceId'),
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async {});
    when(() => seat.applyWorkingSessionSync(
          sessionWorking: any(named: 'sessionWorking'),
          sessionConnecting: any(named: 'sessionConnecting'),
          memberRunning: any(named: 'memberRunning'),
          historyContinueInFlight: any(named: 'historyContinueInFlight'),
        )).thenReturn(HistoryAwaitingWorkingAction.none);
    when(() => seat.load(
          session: any(named: 'session'),
          memberId: any(named: 'memberId'),
          launchContext: any(named: 'launchContext'),
          team: any(named: 'team'),
          workingDirectory: any(named: 'workingDirectory'),
          force: any(named: 'force'),
        )).thenAnswer((_) => Future.value());
    when(() => seat.softReloadOrLoad(
          session: any(named: 'session'),
          memberId: any(named: 'memberId'),
          launchContext: any(named: 'launchContext'),
          team: any(named: 'team'),
          workingDirectory: any(named: 'workingDirectory'),
        )).thenAnswer((_) => Future.value());
  });
  tearDown(tearDownTestAppStorage);

  Future<void> pumpSession(
    WidgetTester tester, {
    required AppSession session,
    required WorkspaceProjectConfigRepository projectConfigRepository,
    PluginState pluginState = const PluginState(),
  }) async {
    final workspace = Workspace(
      workspaceId: 'ws-1',
      folders: const [WorkspaceFolder(path: '/work')],
      createdAt: 1,
    );

    final chatCubit = _MockChatCubit();
    final aiHistoryCubit = _MockAiHistoryCubit();
    final cliPresetsCubit = _MockCliPresetsCubit();
    final launchProfileCubit = _MockLaunchProfileCubit();
    final pluginCubit = _MockPluginCubit();
    final skillCubit = _MockSkillCubit();
    final sessionPreferencesCubit = _MockSessionPreferencesCubit();
    final appProviderCubit = _MockAppProviderCubit();
    final expertHubCubit = _MockExpertHubCubit();
    final agentAttentionCubit = _MockAgentAttentionCubit();
    final editorCubit = _MockEditorCubit();
    final worktreeCubit = _MockWorktreeCubit();
    final memberPresenceCubit = _MockMemberPresenceCubit();
    final layoutCubit = _MockLayoutCubit();
    final workbenchCubit = WorkbenchCubit();
    final lifecycle = _MockSessionLifecycleService();
    when(() => lifecycle.launchWorkTarget(
          any(),
          memberId: any(named: 'memberId'),
        )).thenReturn(RuntimeTarget.local());

    _stubCubit(chatCubit, ChatState(workspaces: [workspace]));
    _stubCubit(aiHistoryCubit, const AiHistoryState());
    _stubCubit(cliPresetsCubit, const CliPresetsState());
    _stubCubit(launchProfileCubit, const LaunchProfileState());
    _stubCubit(pluginCubit, pluginState);
    _stubCubit(
      skillCubit,
      const SkillState(installed: [
        Skill(
          id: 'ws-skill',
          name: 'Plan Ws',
          description: '',
          directory: 'plan-ws',
          installedAt: 0,
          updatedAt: 0,
          enabled: true,
        ),
        Skill(
          id: 'other-skill',
          name: 'Secret Skill',
          description: '',
          directory: 'secret',
          installedAt: 0,
          updatedAt: 0,
          enabled: true,
        ),
      ]),
    );
    _stubCubit(sessionPreferencesCubit, SessionPreferencesState());
    _stubCubit(appProviderCubit, const AppProviderState());
    _stubCubit(expertHubCubit, const ExpertHubState());
    _stubCubit(agentAttentionCubit, const AgentAttentionState());
    _stubCubit(editorCubit, const EditorState());
    _stubCubit(worktreeCubit, const WorktreeState());
    _stubCubit(memberPresenceCubit, const MemberPresenceState());
    _stubCubit(layoutCubit, const LayoutState());
    when(() => chatCubit.isMemberWorking(any(), any())).thenReturn(false);
    when(() => chatCubit.isMemberRunning(
          sessionId: any(named: 'sessionId'),
          memberId: any(named: 'memberId'),
        )).thenReturn(false);
    when(() => chatCubit.lifecycle).thenReturn(lifecycle);
    when(() => chatCubit.followUpQueue).thenReturn(
      InMemoryFollowUpQueueStore(),
    );
    when(() => chatCubit.tabStore).thenReturn(ChatTabStore());
    when(() => aiHistoryCubit.ensureSeat(
          sessionId: any(named: 'sessionId'),
          selectedMemberId: any(named: 'selectedMemberId'),
        )).thenReturn(seat);
    when(() => worktreeCubit.worktreesForProject(any())).thenReturn(const []);

    final theme = buildDarkTheme();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<CommandBus>(create: (_) => CommandBus()),
        ],
        child: MultiBlocProvider(providers: [
          BlocProvider<ChatCubit>.value(value: chatCubit),
          BlocProvider<AiHistoryCubit>.value(value: aiHistoryCubit),
          BlocProvider<CliPresetsCubit>.value(value: cliPresetsCubit),
          BlocProvider<LaunchProfileCubit>.value(value: launchProfileCubit),
          BlocProvider<PluginCubit>.value(value: pluginCubit),
          BlocProvider<SkillCubit>.value(value: skillCubit),
          BlocProvider<SessionPreferencesCubit>.value(
            value: sessionPreferencesCubit,
          ),
          BlocProvider<AppProviderCubit>.value(value: appProviderCubit),
          BlocProvider<ExpertHubCubit>.value(value: expertHubCubit),
          BlocProvider<AgentAttentionCubit>.value(
            value: agentAttentionCubit,
          ),
          BlocProvider<EditorCubit>.value(value: editorCubit),
          BlocProvider<WorktreeCubit>.value(value: worktreeCubit),
          BlocProvider<MemberPresenceCubit>.value(
            value: memberPresenceCubit,
          ),
          BlocProvider<LayoutCubit>.value(value: layoutCubit),
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
                body: SessionChatView(
                  session: session,
                  workspace: workspace,
                  selectedMemberId: '',
                  projectConfigRepository: projectConfigRepository,
                  onSubmit: (_) async => const HistoryContinueSubmitResult(
                    ok: true,
                    channel: HistoryContinueChannel.pty,
                  ),
                ),
              ),
            ),
          ),
        ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppSession session(String id, {CliTool cli = CliTool.claude}) => AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/work')],
    cli: cli,
    createdAt: 1,
  );

  WorkspaceProjectConfigRepository projectRepository(
    InMemoryFilesystem fs,
  ) {
    return WorkspaceProjectConfigRepository(
      fs: fs,
      layout: WorkspaceLayout(teampilotRoot: '/test-root'),
    );
  }

  testWidgets('slash menu shows workspace-only skill from project-config',
      (tester) async {
    final fs = InMemoryFilesystem();
    final repository = projectRepository(fs);
    await repository.save(
      'ws-1',
      const WorkspaceProjectConfig(bundle: ConfigBundle(skillIds: [
        'ws-skill',
      ])),
    );

    await pumpSession(
      tester,
      session: session('s1'),
      projectConfigRepository: repository,
    );

    await tester.enterText(find.byType(TextField).first, '/plan');
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.text('Plan Ws'), findsOneWidget);
  });

  testWidgets('slash menu hides skill not enabled in workspace bundle',
      (tester) async {
    final fs = InMemoryFilesystem();
    final repository = projectRepository(fs);
    await repository.save(
      'ws-1',
      const WorkspaceProjectConfig(bundle: ConfigBundle(skillIds: [
        'ws-skill',
      ])),
    );

    await pumpSession(
      tester,
      session: session('s2'),
      projectConfigRepository: repository,
    );

    await tester.enterText(find.byType(TextField).first, '/sec');
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.text('Secret Skill'), findsNothing);
  });

  testWidgets(
    'existing session resolves OpenCode commands with enabled skills and plugins',
    (tester) async {
      final fs = InMemoryFilesystem();
      final repository = projectRepository(fs);
      await repository.save(
        'ws-1',
        const WorkspaceProjectConfig(bundle: ConfigBundle(
          skillIds: ['ws-skill'],
          pluginIds: ['review-plugin'],
        )),
      );

      await pumpSession(
        tester,
        session: session('s3', cli: CliTool.opencode),
        projectConfigRepository: repository,
        pluginState: const PluginState(installed: [
          Plugin(
            id: 'review-plugin',
            name: 'Review Plugin',
            description: '',
            version: '1.0',
            directory: 'review-plugin',
            installedAt: 0,
            updatedAt: 0,
            capabilities: PluginCapabilities(
              commands: [PluginCommand(name: 'review')],
            ),
          ),
        ]),
      );

      final field = tester.widget<ComposeTriggerField>(
        find.byType(ComposeTriggerField),
      );
      expect(field.nativeCommands.map((command) => command.name), [
        'compact',
        'help',
      ]);
      final candidates = buildComposeSlashCandidates(
        skills: field.skills,
        plugins: field.plugins,
        enabledBundle: field.slashBundle,
        query: '',
        syntax: field.skillSyntax,
        nativeCommands: field.nativeCommands,
      );
      expect(candidates.map((candidate) => candidate.insertText), [
        ' /plan-ws',
        '/compact ',
        '/help',
        '/review',
      ]);
    },
  );
}
