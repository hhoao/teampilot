import 'dart:async';

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
import 'package:teampilot/models/failed_message_record.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/session_activity.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/pages/chat/operator_history_send.dart'
    show OperatorMailboxQueuedEvent;
import 'package:teampilot/pages/chat/session_chat_view.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/compose/compose_draft_cache.dart';
import 'package:teampilot/services/follow_up/follow_up_queue.dart';
import 'package:teampilot/services/session/failed_message_store.dart';
import 'package:teampilot/services/session/history_awaiting_working_sync.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/theme/app_theme.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

class _MockChatCubit extends Mock implements ChatCubit {
  @override
  final Map<String, double> sessionScrollAnchors = {};
}

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

AppSession _session(String sessionId, {CliTool cli = CliTool.claude}) =>
    AppSession(
      sessionId: sessionId,
      workspaceId: 'ws-1',
      folders: const [WorkspaceFolder(path: '/work')],
      cli: cli,
      createdAt: 1,
    );

class _Harness {
  _Harness(this.tester) {
    addTearDown(routeActive.dispose);
    addTearDown(chatStates.close);
  }

  final WidgetTester tester;
  final ValueNotifier<bool> routeActive = ValueNotifier<bool>(false);
  final StreamController<ChatState> chatStates =
      StreamController<ChatState>.broadcast();

  late _MockChatCubit chatCubit;
  late _MockAiHistorySeat seat;
  late _MockAiHistoryCubit aiHistoryCubit;
  late _MockCliPresetsCubit cliPresetsCubit;
  late _MockLaunchProfileCubit launchProfileCubit;
  late _MockPluginCubit pluginCubit;
  late _MockSkillCubit skillCubit;
  late _MockSessionPreferencesCubit sessionPreferencesCubit;
  late _MockAppProviderCubit appProviderCubit;
  late _MockExpertHubCubit expertHubCubit;
  late _MockAgentAttentionCubit agentAttentionCubit;
  late _MockEditorCubit editorCubit;
  late _MockWorktreeCubit worktreeCubit;
  late _MockMemberPresenceCubit memberPresenceCubit;
  late _MockLayoutCubit layoutCubit;
  late _MockSessionLifecycleService lifecycle;
  final WorkbenchCubit workbenchCubit = WorkbenchCubit();

  ChatState chatState = const ChatState();
  AiHistoryState seatState = const AiHistoryState();
  bool memberRunning = false;
  bool hasDocument = true;
  AppSession? hydratedDocument;
  AppSession session = _session('s1');

  /// When set, [AiHistorySeat.softReloadOrLoad] awaits this gate so a load can
  /// be held in flight across a seat change.
  Completer<void>? softLoadGate;

  static final Workspace _workspace = Workspace(
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/work')],
    createdAt: 1,
  );

  Future<void> pump({
    required AppSession session,
    bool active = false,
    AiHistoryState? seatState,
  }) async {
    this.session = session;
    this.seatState = seatState ?? const AiHistoryState();
    chatState = ChatState(workspaces: [_workspace]);
    routeActive.value = active;
    _createMocks();
    await _pumpSubtree();
  }

  /// Re-pumps the SAME mounted subtree with a new [session], reusing the
  /// existing mocks/providers so [SessionChatView]'s [State.didUpdateWidget]
  /// seat-change path runs against the same seat.
  Future<void> repump({required AppSession session}) async {
    this.session = session;
    await _pumpSubtree();
  }

  void _createMocks() {
    chatCubit = _MockChatCubit();
    seat = _MockAiHistorySeat();
    when(() => seat.state).thenAnswer((_) => seatState);
    when(
      () => seat.stream,
    ).thenAnswer((_) => const Stream<AiHistoryState>.empty());
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
    when(
      () => seat.applyWorkingSessionSync(
        sessionWorking: any(named: 'sessionWorking'),
        sessionConnecting: any(named: 'sessionConnecting'),
        memberRunning: any(named: 'memberRunning'),
        historyContinueInFlight: any(named: 'historyContinueInFlight'),
      ),
    ).thenReturn(HistoryAwaitingWorkingAction.none);
    when(
      () => seat.load(
        session: any(named: 'session'),
        memberId: any(named: 'memberId'),
        launchContext: any(named: 'launchContext'),
        team: any(named: 'team'),
        workingDirectory: any(named: 'workingDirectory'),
        force: any(named: 'force'),
      ),
    ).thenAnswer((_) => Future.value());
    when(
      () => seat.softReloadOrLoad(
        session: any(named: 'session'),
        memberId: any(named: 'memberId'),
        launchContext: any(named: 'launchContext'),
        team: any(named: 'team'),
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) => softLoadGate?.future ?? Future.value());

    aiHistoryCubit = _MockAiHistoryCubit();
    cliPresetsCubit = _MockCliPresetsCubit();
    launchProfileCubit = _MockLaunchProfileCubit();
    pluginCubit = _MockPluginCubit();
    skillCubit = _MockSkillCubit();
    sessionPreferencesCubit = _MockSessionPreferencesCubit();
    appProviderCubit = _MockAppProviderCubit();
    expertHubCubit = _MockExpertHubCubit();
    agentAttentionCubit = _MockAgentAttentionCubit();
    editorCubit = _MockEditorCubit();
    worktreeCubit = _MockWorktreeCubit();
    memberPresenceCubit = _MockMemberPresenceCubit();
    layoutCubit = _MockLayoutCubit();
    lifecycle = _MockSessionLifecycleService();
    when(
      () => lifecycle.launchWorkTarget(any(), memberId: any(named: 'memberId')),
    ).thenReturn(RuntimeTarget.local());

    when(() => chatCubit.state).thenAnswer((_) => chatState);
    when(() => chatCubit.stream).thenAnswer((_) => chatStates.stream);
    when(() => chatCubit.isMemberWorking(any(), any())).thenReturn(false);
    when(
      () => chatCubit.isMemberRunning(
        sessionId: any(named: 'sessionId'),
        memberId: any(named: 'memberId'),
      ),
    ).thenAnswer((_) => memberRunning);
    when(
      () => chatCubit.sessionHasDocument(any()),
    ).thenAnswer((_) => hasDocument);
    when(
      () => chatCubit.hydrateSessionDocument(any(), any()),
    ).thenAnswer((_) async => hydratedDocument);
    when(() => chatCubit.lifecycle).thenReturn(lifecycle);
    when(
      () => chatCubit.followUpQueue,
    ).thenReturn(InMemoryFollowUpQueueStore());
    when(
      () => chatCubit.tabStore,
    ).thenReturn(ChatTabStore(storage: testHomeStorage));
    when(
      () => chatCubit.operatorMailboxQueued,
    ).thenAnswer((_) => const Stream<OperatorMailboxQueuedEvent>.empty());
    when(() => worktreeCubit.worktreesForProject(any())).thenReturn(const []);

    _stubCubit(aiHistoryCubit, const AiHistoryState());
    when(
      () => aiHistoryCubit.ensureSeat(
        sessionId: any(named: 'sessionId'),
        selectedMemberId: any(named: 'selectedMemberId'),
      ),
    ).thenReturn(seat);
    _stubCubit(cliPresetsCubit, const CliPresetsState());
    _stubCubit(launchProfileCubit, const LaunchProfileState());
    _stubCubit(pluginCubit, const PluginState());
    _stubCubit(skillCubit, const SkillState());
    _stubCubit(sessionPreferencesCubit, SessionPreferencesState());
    _stubCubit(appProviderCubit, const AppProviderState());
    _stubCubit(expertHubCubit, const ExpertHubState());
    _stubCubit(agentAttentionCubit, const AgentAttentionState());
    _stubCubit(editorCubit, const EditorState());
    _stubCubit(worktreeCubit, const WorktreeState());
    _stubCubit(memberPresenceCubit, const MemberPresenceState());
    _stubCubit(layoutCubit, const LayoutState());
  }

  Future<void> _pumpSubtree() async {
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
            BlocProvider<AgentAttentionCubit>.value(value: agentAttentionCubit),
            BlocProvider<EditorCubit>.value(value: editorCubit),
            BlocProvider<WorktreeCubit>.value(value: worktreeCubit),
            BlocProvider<MemberPresenceCubit>.value(value: memberPresenceCubit),
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
                data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1),
                child: Scaffold(
                  body: ValueListenableBuilder<bool>(
                    valueListenable: routeActive,
                    builder: (_, active, __) => SessionChatView(
                      session: session,
                      workspace: _workspace,
                      selectedMemberId: '',
                      routeActive: active,
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
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> setRouteActive(bool active) async {
    routeActive.value = active;
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> setRunning() async {
    memberRunning = true;
    chatState = chatState.copyWith(
      sessionActivities: {
        session.sessionId: const SessionActivity(
          reasons: {SessionBusyReason.inTurn},
        ),
      },
    );
    chatStates.add(chatState);
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeFailedMessageStore());
    registerFallbackValue(
      FailedMessageRecord(
        id: 'fb',
        text: '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
    );
    final fbWorkspace = Workspace(workspaceId: 'ws-fb', createdAt: 0);
    final fbSession = AppSession(
      sessionId: 'fb',
      workspaceId: 'ws-fb',
      folders: const [],
      createdAt: 0,
    );
    registerFallbackValue(fbSession);
    registerFallbackValue(
      WorkspaceLaunchContext(
        session: fbSession,
        workspace: fbWorkspace,
        usesPosixPaths: false,
      ),
    );
    registerFallbackValue(
      const TeamProfile(
        id: 'fb',
        name: 'fb',
        teamMode: TeamMode.native,
        members: [],
      ),
    );
  });

  setUp(() {
    setUpTestAppStorage();
    installTestHomeStorage(
      filesystem: InMemoryFilesystem(),
      paths: const AppPaths('/load-gating'),
      home: '/load-gating',
      cwd: '/load-gating',
    );
    composeDraftCache.clear();
  });
  tearDown(tearDownTestAppStorage);

  void verifyNoLoad(_Harness h) {
    verifyNever(
      () => h.seat.softReloadOrLoad(
        session: any(named: 'session'),
        memberId: any(named: 'memberId'),
        launchContext: any(named: 'launchContext'),
        team: any(named: 'team'),
        workingDirectory: any(named: 'workingDirectory'),
      ),
    );
    verifyNever(
      () => h.seat.load(
        session: any(named: 'session'),
        memberId: any(named: 'memberId'),
        launchContext: any(named: 'launchContext'),
        team: any(named: 'team'),
        workingDirectory: any(named: 'workingDirectory'),
        force: any(named: 'force'),
      ),
    );
  }

  void verifySoftLoad(_Harness h) {
    verify(
      () => h.seat.softReloadOrLoad(
        session: any(named: 'session'),
        memberId: any(named: 'memberId'),
        launchContext: any(named: 'launchContext'),
        team: any(named: 'team'),
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).called(1);
  }

  testWidgets('offstage cold mount defers history load', (tester) async {
    final h = _Harness(tester);
    await h.pump(session: _session('s1'));
    verifyNoLoad(h);
  });

  testWidgets('hot mount loads history once', (tester) async {
    final h = _Harness(tester);
    await h.pump(session: _session('s1'), active: true);
    verifySoftLoad(h);
  });

  testWidgets('activating a deferred tab loads history', (tester) async {
    final h = _Harness(tester);
    await h.pump(session: _session('s1'));
    verifyNoLoad(h);
    await h.setRouteActive(true);
    verifySoftLoad(h);
  });

  testWidgets('running flip loads a deferred seat', (tester) async {
    final h = _Harness(tester);
    await h.pump(session: _session('s1'));
    verifyNoLoad(h);
    await h.setRunning();
    verifySoftLoad(h);
  });

  testWidgets('cold hot mount hydrates the document before load', (
    tester,
  ) async {
    final h = _Harness(tester)
      ..hasDocument = false
      ..hydratedDocument = _session('s1', cli: CliTool.cursor);
    await h.pump(session: _session('s1'), active: true);
    verify(() => h.chatCubit.hydrateSessionDocument('ws-1', 's1')).called(1);
    final loaded =
        verify(
              () => h.seat.softReloadOrLoad(
                session: captureAny(named: 'session'),
                memberId: any(named: 'memberId'),
                launchContext: any(named: 'launchContext'),
                team: any(named: 'team'),
                workingDirectory: any(named: 'workingDirectory'),
              ),
            ).captured.single
            as AppSession;
    expect(loaded.cli, CliTool.cursor);
  });

  testWidgets('ready hot mount does not re-hydrate the document', (
    tester,
  ) async {
    final h = _Harness(tester)..hasDocument = false;
    await h.pump(
      session: _session('s1'),
      active: true,
      seatState: const AiHistoryState(
        status: AiHistoryViewStatus.ready,
        sessionId: 's1',
        memberId: '',
      ),
    );
    verifyNever(() => h.chatCubit.hydrateSessionDocument(any(), any()));
    verifySoftLoad(h);
  });

  testWidgets('seat change during an in-flight load still loads the new seat', (
    tester,
  ) async {
    final h = _Harness(tester)..softLoadGate = Completer<void>();
    await h.pump(session: _session('s1'), active: true);
    final appSessionB = _session('s2');
    await h.repump(session: appSessionB);
    final loadedSessions = verify(
      () => h.seat.softReloadOrLoad(
        session: captureAny(named: 'session'),
        memberId: any(named: 'memberId'),
        launchContext: any(named: 'launchContext'),
        team: any(named: 'team'),
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).captured.map((s) => (s as AppSession).sessionId);
    expect(loadedSessions, contains('s2'));
  });
}
