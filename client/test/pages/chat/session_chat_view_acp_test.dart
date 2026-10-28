import 'dart:async';

import 'package:acpd/acpd.dart' as acpd;
import 'package:ai_message_core/ai_message_core.dart'
    show
        AiAskUserOption,
        AiAskUserQuestion,
        AiMessage,
        AiRole,
        AiTextPart,
        ExternalStoreAiThreadRuntime;
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/ai_history_cubit.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
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
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/pages/chat/acp_ask_card.dart';
import 'package:teampilot/pages/chat/acp_permission_card.dart';
import 'package:teampilot/pages/chat/acp_plan_card.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/pages/chat/operator_history_send.dart'
    show OperatorMailboxQueuedEvent;
import 'package:teampilot/pages/chat/session_chat_view.dart';
import 'package:teampilot/services/acp/acp_chat_transcript_replay.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_draft_cache.dart';
import 'package:teampilot/services/chat/conversation/follow_up/follow_up_queue.dart';
import 'package:teampilot/services/chat/conversation/history/failed_message_store.dart';
import 'package:teampilot/services/chat/conversation/history/history_awaiting_working_sync.dart';
import 'package:teampilot/services/chat/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/widgets/compose/workspace_compose_card.dart';
import 'package:teampilot/widgets/follow_up/follow_up_queue_strip.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

/// `SessionChatMessageArea` reads the non-nullable `sessionScrollAnchors`
/// field, so the mock must provide a real empty map instead of mocktail's
/// implicit null.
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

/// All-stub [AcpSessionRuntimeApi] (same shape as the cubit test fake).
class _FakeAcpRuntime implements AcpSessionRuntimeApi {
  final permissionsController =
      StreamController<AgentPermissionRequest>.broadcast();
  final clientRequestsController =
      StreamController<AcpPendingClientRequest>.broadcast();

  ({AgentPermissionReplyKind kind, AgentPermissionAlwaysOption? always})?
  lastAnswer;
  AcpAskHoldReply? lastAsk;
  AcpPlanHoldReply? lastPlan;

  @override
  Future<void> start({
    required CliTool tool,
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
    List<acpd.McpServer> mcpServers = const [],
    LaunchSecurityPolicy permissionPolicy = LaunchSecurityPolicy.fullAccess,
    String? resumeSessionId,
  }) async {}

  @override
  void setPermissionPolicy(LaunchSecurityPolicy policy) {}

  @override
  bool get isStarted => true;

  @override
  String get sessionId => 'acp-session-1';

  @override
  Future<void> prompt(String text) async => prompts.add(text);

  /// Every prompt the runtime accepted (turn guard regressions).
  final prompts = <String>[];

  @override
  Stream<AcpSessionUpdate> get updates => const Stream.empty();

  @override
  Stream<AgentPermissionRequest> get permissionRequests =>
      permissionsController.stream;

  @override
  Stream<AcpPendingClientRequest> get clientRequests =>
      clientRequestsController.stream;

  @override
  AcpAuthNotice? get lastAuthNotice => null;

  @override
  Future<int>? get agentProcessExitCode => null;

  @override
  Future<AgentPermissionReplyKind?> answerPermission(
    AgentPermissionReplyKind reply, {
    AgentPermissionAlwaysOption? always,
  }) async {
    lastAnswer = (kind: reply, always: always);
    return reply;
  }

  @override
  Future<void> answerAsk(AcpAskHoldReply reply) async {
    lastAsk = reply;
  }

  @override
  Future<void> answerPlan(AcpPlanHoldReply reply) async {
    lastPlan = reply;
  }

  @override
  void cancel() => cancelled = true;

  bool cancelled = false;

  @override
  Future<void> close() async {}
}

const _request = AgentPermissionRequest(
  id: 'perm-1',
  description: 'Run `npm install`',
  always: [AgentPermissionAlwaysOption(label: 'Bash', payload: 'opt-9')],
);

void _stubCubit<TState>(Cubit<TState> cubit, TState state) {
  when(() => cubit.state).thenReturn(state);
  when(() => cubit.stream).thenAnswer((_) => Stream<TState>.empty());
}

/// Integration regression: `SessionChatComposeSection` reads the ACP runtime's
/// pending permission via `seatSelect` (context.select), which requires a
/// `BlocProvider<AcpChatRuntimeCubit>` in the ancestor chain. The runtime used
/// to arrive only as a constructor arg (no provider anywhere), so the chat
/// center crashed with ProviderNotFoundException at first build. This test
/// pumps the real `SessionChatView` subtree with a live cubit — the path the
/// round-1 card tests (which pumped `AcpPermissionCard` directly) missed.
void main() {
  late _MockAiHistorySeat seat;
  late InMemoryFilesystem memoryFs;

  setUpAll(() {
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
    registerFallbackValue(_FakeFailedMessageStore());
    registerFallbackValue(<AiMessage>[]);
    registerFallbackValue(
      FailedMessageRecord(
        id: 'fb-pending',
        text: 'fb',
        createdAt: DateTime.utc(2020),
      ),
    );
  });

  setUp(() {
    setUpTestAppStorage();
    memoryFs = InMemoryFilesystem();
    installTestHomeStorage(
      filesystem: memoryFs,
      paths: const AppPaths('/acp-chat-view-test'),
      home: '/acp-chat-view-test',
      cwd: '/acp-chat-view-test',
    );
    composeDraftCache.clear();

    seat = _MockAiHistorySeat();
    _stubCubit(seat, const AiHistoryState());
    when(() => seat.isClosed).thenReturn(false);
    when(() => seat.subagentAttachments).thenReturn(const {});
    when(() => seat.runtime).thenReturn(ExternalStoreAiThreadRuntime());
    when(() => seat.loadedMessages).thenReturn(const []);
    when(() => seat.pendingDeliveryStatuses).thenReturn(const {});
    when(() => seat.hasOptimisticPending).thenReturn(false);
    when(() => seat.markExternalLoading()).thenReturn(null);
    when(() => seat.adoptExternalMessages(any())).thenReturn(null);
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
    ).thenAnswer((_) => Future.value());
  });
  tearDown(tearDownTestAppStorage);

  Future<({_MockChatCubit chatCubit, InMemoryFollowUpQueueStore followUpQueue})>
  pumpSession(
    WidgetTester tester, {
    required AppSession session,
    AcpChatRuntimeCubit? acpRuntime,
    String selectedMemberId = '',
    Future<HistoryContinueSubmitResult> Function(String message)? onSubmit,
    bool memberWorking = false,
    InMemoryFollowUpQueueStore? followUpQueueStore,
  }) async {
    final workspace = Workspace(
      workspaceId: 'ws-1',
      folders: const [],
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
    when(
      () => lifecycle.launchWorkTarget(any(), memberId: any(named: 'memberId')),
    ).thenReturn(RuntimeTarget.local());

    _stubCubit(chatCubit, ChatState(workspaces: [workspace]));
    _stubCubit(aiHistoryCubit, const AiHistoryState());
    _stubCubit(cliPresetsCubit, const CliPresetsState());
    _stubCubit(launchProfileCubit, const LaunchProfileState());
    when(() => launchProfileCubit.byId(any())).thenReturn(null);
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
    when(
      () => chatCubit.isMemberWorking(any(), any()),
    ).thenReturn(memberWorking);
    when(
      () => chatCubit.isMemberRunning(
        sessionId: any(named: 'sessionId'),
        memberId: any(named: 'memberId'),
      ),
    ).thenReturn(false);
    // Cold-load hydration is a live ChatCubit concern (document store); the
    // harness has no persisted session document, so return null.
    when(
      () => chatCubit.hydrateSessionDocument(any(), any()),
    ).thenAnswer((_) async => null);
    when(() => chatCubit.lifecycle).thenReturn(lifecycle);
    final followUpQueue = followUpQueueStore ?? InMemoryFollowUpQueueStore();
    when(() => chatCubit.followUpQueue).thenReturn(followUpQueue);
    when(
      () => chatCubit.tabStore,
    ).thenReturn(ChatTabStore(storage: testHomeStorage));
    when(
      () => chatCubit.operatorMailboxQueued,
    ).thenAnswer((_) => const Stream<OperatorMailboxQueuedEvent>.empty());
    when(
      () => aiHistoryCubit.ensureSeat(
        sessionId: any(named: 'sessionId'),
        selectedMemberId: any(named: 'selectedMemberId'),
      ),
    ).thenReturn(seat);

    final theme = buildDarkTheme();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<HomeStorage>.value(value: testHomeStorage),
          RepositoryProvider<CommandBus>(create: (_) => CommandBus()),
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
                  body: SessionChatView(
                    session: session,
                    workspace: workspace,
                    selectedMemberId: selectedMemberId,
                    acpRuntime: acpRuntime,
                    onSubmit:
                        onSubmit ??
                        (_) async => const HistoryContinueSubmitResult(
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
    return (chatCubit: chatCubit, followUpQueue: followUpQueue);
  }

  AppSession session(String id, {bool acp = false}) => AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    folders: const [],
    cli: CliTool.gemini,
    acp: acp,
    createdAt: 1,
  );

  /// Mixed team: lead is an ACP seat, worker stays on the PTY.
  AppSession mixedTeamSession() => AppSession(
    sessionId: 's-mixed',
    workspaceId: 'ws-1',
    folders: const [],
    sessionTeam: 'team-1',
    createdAt: 1,
    members: const [
      SessionMemberBinding(
        rosterMemberId: 'lead',
        taskId: 'task-lead',
        acp: true,
      ),
      SessionMemberBinding(rosterMemberId: 'worker', taskId: 'task-worker'),
    ],
  );

  void stubPtyPendingDelivery() {
    when(
      () => seat.persistPendingUser(
        store: any(named: 'store'),
        workspaceId: any(named: 'workspaceId'),
        sessionId: any(named: 'sessionId'),
        text: any(named: 'text'),
      ),
    ).thenAnswer((invocation) async {
      return FailedMessageRecord(
        id: 'pending:test',
        text: invocation.namedArguments[#text] as String,
        createdAt: DateTime.utc(2020),
      );
    });
    when(
      () => seat.markPendingFailed(
        store: any(named: 'store'),
        workspaceId: any(named: 'workspaceId'),
        sessionId: any(named: 'sessionId'),
        record: any(named: 'record'),
      ),
    ).thenAnswer((_) async {});
  }

  Future<void> enterCompose(WidgetTester tester, String text) async {
    final composeField = find.descendant(
      of: find.byType(TpTokenTextField),
      matching: find.byType(TextField),
    );
    expect(composeField, findsOneWidget);
    await tester.enterText(composeField, text);
    await tester.pump();
    expect(tester.widget<TextField>(composeField).controller?.text, text);
    expect(
      tester
          .widget<WorkspaceComposeCard>(find.byType(WorkspaceComposeCard))
          .controller
          .text,
      text,
    );
  }

  Future<void> submitCompose(WidgetTester tester) async {
    tester
        .widget<WorkspaceComposeCard>(find.byType(WorkspaceComposeCard))
        .onSubmit();
    await tester.pumpAndSettle();
  }

  void countPtyHistoryLoads(List<int> loads) {
    when(
      () => seat.load(
        session: any(named: 'session'),
        memberId: any(named: 'memberId'),
        launchContext: any(named: 'launchContext'),
        team: any(named: 'team'),
        workingDirectory: any(named: 'workingDirectory'),
        force: any(named: 'force'),
      ),
    ).thenAnswer((_) async {
      loads.add(1);
    });
    when(
      () => seat.softReloadOrLoad(
        session: any(named: 'session'),
        memberId: any(named: 'memberId'),
        launchContext: any(named: 'launchContext'),
        team: any(named: 'team'),
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async {
      loads.add(1);
    });
  }

  testWidgets(
    'ACP chat view builds and renders the permission card through the '
    'provided runtime cubit',
    (tester) async {
      final runtime = _FakeAcpRuntime();
      final cubit = AcpChatRuntimeCubit(
        runtime: runtime,
        sessionId: 's1',
        tool: CliTool.gemini,
      );
      addTearDown(() async {
        await cubit.close();
        await runtime.permissionsController.close();
        await runtime.clientRequestsController.close();
      });

      // Cubit lifecycle (start + stream delivery) needs the real event loop
      // on this SDK — the repo's tester.runAsync workaround.
      await tester.runAsync(() async {
        await cubit.start(
          executable: 'gemini',
          sessionToolDir: '/tmp/tool',
          workingDirectory: '/w',
        );
      });

      // No ProviderNotFoundException from the compose section's seatSelect.
      await pumpSession(tester, session: session('s1'), acpRuntime: cubit);
      expect(tester.takeException(), isNull);

      await tester.runAsync(() async {
        runtime.permissionsController.add(_request);
        await Future<void>.delayed(Duration.zero);
      });
      expect(cubit.state.pendingPermission, _request);
      await tester.pump();

      expect(find.byType(AcpPermissionCard), findsOneWidget);
      expect(find.byKey(AiPermissionCard.cardKey), findsOneWidget);
      expect(find.textContaining('npm install'), findsOneWidget);

      // Answering through the real card clears the hold and unmounts it.
      await tester.tap(find.byKey(AiPermissionCard.allowOnceButtonKey));
      await tester.pumpAndSettle();

      expect(runtime.lastAnswer?.kind, AgentPermissionReplyKind.allowOnce);
      expect(cubit.state.pendingPermission, isNull);
      expect(find.byType(AcpPermissionCard), findsNothing);
    },
  );

  testWidgets('non-ACP session still builds without an ACP runtime', (
    tester,
  ) async {
    await pumpSession(tester, session: session('s2'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ACP session without a runtime yet does not load PTY transcript history',
    (tester) async {
      var ptyHistoryLoads = 0;
      when(
        () => seat.load(
          session: any(named: 'session'),
          memberId: any(named: 'memberId'),
          launchContext: any(named: 'launchContext'),
          team: any(named: 'team'),
          workingDirectory: any(named: 'workingDirectory'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async {
        ptyHistoryLoads++;
      });
      when(
        () => seat.softReloadOrLoad(
          session: any(named: 'session'),
          memberId: any(named: 'memberId'),
          launchContext: any(named: 'launchContext'),
          team: any(named: 'team'),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async {
        ptyHistoryLoads++;
      });

      await pumpSession(tester, session: session('s-acp', acp: true));
      expect(tester.takeException(), isNull);
      expect(ptyHistoryLoads, 0);
      verify(() => seat.markExternalLoading()).called(greaterThan(0));
    },
  );

  testWidgets(
    'cold ACP session without a runtime paints the app transcript snapshot',
    (tester) async {
      final loads = <int>[];
      countPtyHistoryLoads(loads);
      final path = testHomeStorage.context.layout.pathContext.join(
        testHomeStorage.context.layout.workspace.sessionRuntimeDir(
          'ws-1',
          's-acp',
        ),
        'acp-transcript.jsonl',
      );
      await memoryFs.atomicWrite(
        path,
        encodeAcpChatTranscript([
          AiMessage(
            id: 'u1',
            role: AiRole.user,
            parts: [AiTextPart(text: 'hello from disk')],
            createdAt: DateTime.utc(2020),
          ),
        ]),
      );

      await pumpSession(tester, session: session('s-acp', acp: true));

      expect(tester.takeException(), isNull);
      expect(
        loads,
        isEmpty,
        reason: 'ACP must never use the PTY transcript loader',
      );
      final adopted = verify(
        () => seat.adoptExternalMessages(captureAny()),
      ).captured;
      expect(adopted, isNotEmpty);
      final messages = adopted.last as List<AiMessage>;
      expect(messages.map((m) => m.id), contains('u1'));
    },
  );

  testWidgets(
    'ACP session with an empty snapshot settles on the empty pane, not loading',
    (tester) async {
      await pumpSession(tester, session: session('s-empty', acp: true));

      expect(tester.takeException(), isNull);
      final adopted = verify(
        () => seat.adoptExternalMessages(captureAny()),
      ).captured;
      expect(adopted, isNotEmpty, reason: 'the loading state must be released');
      expect(adopted.last as List<AiMessage>, isEmpty);
    },
  );

  testWidgets(
    'ACP compose without an attached runtime delegates to the host submit hook',
    (tester) async {
      String? submitted;
      var hostSubmissions = 0;
      await pumpSession(
        tester,
        session: session('s-acp', acp: true),
        onSubmit: (message) async {
          hostSubmissions++;
          submitted = message;
          return const HistoryContinueSubmitResult(
            ok: true,
            channel: HistoryContinueChannel.pty,
          );
        },
      );

      await enterCompose(tester, 'continue please');
      await submitCompose(tester);

      expect(hostSubmissions, 1);
      expect(submitted, 'continue please');
      // Terminal-less seats never write PTY pending records.
      verifyNever(
        () => seat.persistPendingUser(
          store: any(named: 'store'),
          workspaceId: any(named: 'workspaceId'),
          sessionId: any(named: 'sessionId'),
          text: any(named: 'text'),
        ),
      );
    },
  );

  testWidgets('ACP compose Stop cancels the in-flight turn via the runtime', (
    tester,
  ) async {
    final runtime = _FakeAcpRuntime();
    final cubit = AcpChatRuntimeCubit(
      runtime: runtime,
      sessionId: 's1',
      tool: CliTool.gemini,
    );
    addTearDown(() async {
      await cubit.close();
      await runtime.permissionsController.close();
      await runtime.clientRequestsController.close();
    });

    await tester.runAsync(() async {
      await cubit.start(
        executable: 'gemini',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
    });
    final harness = await pumpSession(
      tester,
      session: session('s1'),
      acpRuntime: cubit,
    );
    expect(tester.takeException(), isNull);

    // Start a turn; the compose Stop button must appear (empty compose) and
    // route to the runtime's cancel, not the PTY interrupt path.
    await tester.runAsync(() async {
      cubit.sendPrompt('do work');
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(cubit.state.inTurn, isTrue);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pumpAndSettle();

    expect(runtime.cancelled, isTrue);
    // Same stop semantics as a PTY seat: queued follow-ups must not auto-fire
    // after the cancelled turn.
    verify(() => harness.chatCubit.pauseFollowUpQueue('s1', 's1')).called(1);
  });

  testWidgets(
    'ACP in-turn compose submit queues the follow-up instead of dropping it',
    (tester) async {
      final runtime = _FakeAcpRuntime();
      final cubit = AcpChatRuntimeCubit(
        runtime: runtime,
        sessionId: 's1',
        tool: CliTool.gemini,
      );
      addTearDown(() async {
        await cubit.close();
        await runtime.permissionsController.close();
        await runtime.clientRequestsController.close();
      });
      await tester.runAsync(() async {
        await cubit.start(
          executable: 'gemini',
          sessionToolDir: '/tmp/tool',
          workingDirectory: '/w',
        );
      });
      final harness = await pumpSession(
        tester,
        session: session('s1', acp: true),
        acpRuntime: cubit,
        memberWorking: true,
      );

      await tester.runAsync(() async {
        cubit.sendPrompt('do work');
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(cubit.state.inTurn, isTrue);

      await enterCompose(tester, 'queued next');
      await submitCompose(tester);

      final seatKey = followUpSeatKey('s1', 's1');
      expect(
        harness.followUpQueue.queueFor(seatKey).items.map((m) => m.content),
        ['queued next'],
      );
      expect(find.byKey(kSessionFollowUpQueueStripKey), findsOneWidget);
      // The running turn was not preempted or duplicated.
      expect(runtime.prompts, ['do work']);
    },
  );

  testWidgets('ACP chat view renders the ask card through the compose slot', (
    tester,
  ) async {
    final runtime = _FakeAcpRuntime();
    final cubit = AcpChatRuntimeCubit(
      runtime: runtime,
      sessionId: 's1',
      tool: CliTool.gemini,
    );
    addTearDown(() async {
      await cubit.close();
      await runtime.permissionsController.close();
      await runtime.clientRequestsController.close();
    });

    await tester.runAsync(() async {
      await cubit.start(
        executable: 'gemini',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
    });

    await pumpSession(tester, session: session('s1'), acpRuntime: cubit);
    expect(tester.takeException(), isNull);

    const questions = [
      AiAskUserQuestion(
        question: 'Pick a color?',
        options: [
          AiAskUserOption(label: 'Red'),
          AiAskUserOption(label: 'Blue'),
        ],
      ),
    ];
    await tester.runAsync(() async {
      runtime.clientRequestsController.add(
        const AcpPendingAsk(questions: questions, toolCallId: 'ask-1'),
      );
      await Future<void>.delayed(Duration.zero);
    });
    expect(cubit.state.pendingClient, isA<AcpPendingAsk>());
    await tester.pump();

    expect(find.byType(AcpAskCard), findsOneWidget);
    expect(find.byKey(AiAskUserQuestionCard.cardKey), findsOneWidget);

    await tester.tap(
      find.byKey(
        AiAskUserQuestionCard.optionKey(questionIndex: 0, optionIndex: 0),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AiAskUserQuestionCard.submitButtonKey));
    await tester.pumpAndSettle();

    expect(runtime.lastAsk?.skipped, isFalse);
    expect(runtime.lastAsk?.submission?.optionIndices, [0]);
    expect(cubit.state.pendingClient, isNull);
    expect(find.byType(AcpAskCard), findsNothing);
  });

  testWidgets('ACP chat view renders the plan card through the compose slot', (
    tester,
  ) async {
    final runtime = _FakeAcpRuntime();
    final cubit = AcpChatRuntimeCubit(
      runtime: runtime,
      sessionId: 's1',
      tool: CliTool.gemini,
    );
    addTearDown(() async {
      await cubit.close();
      await runtime.permissionsController.close();
      await runtime.clientRequestsController.close();
    });

    await tester.runAsync(() async {
      await cubit.start(
        executable: 'gemini',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
    });

    await pumpSession(tester, session: session('s1'), acpRuntime: cubit);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      runtime.clientRequestsController.add(
        const AcpPendingPlan(
          toolCallId: 'plan-1',
          planText: 'Ship the ACP ask and plan cards.',
        ),
      );
      await Future<void>.delayed(Duration.zero);
    });
    expect(cubit.state.pendingClient, isA<AcpPendingPlan>());
    await tester.pump();

    expect(find.byType(AcpPlanCard), findsOneWidget);
    expect(find.byKey(AiExitPlanModeCard.cardKey), findsOneWidget);

    await tester.tap(find.byKey(AiExitPlanModeCard.approveButtonKey));
    await tester.pumpAndSettle();

    expect(runtime.lastPlan, isNotNull);
    expect(runtime.lastPlan!.rejected, isFalse);
    expect(runtime.lastPlan!.cancelled, isFalse);
    expect(cubit.state.pendingClient, isNull);
    expect(find.byType(AcpPlanCard), findsNothing);
  });

  testWidgets('mixed ACP seat with a runtime cubit submits to that cubit', (
    tester,
  ) async {
    final runtime = _FakeAcpRuntime();
    final cubit = AcpChatRuntimeCubit(
      runtime: runtime,
      sessionId: 's-mixed',
      tool: CliTool.gemini,
      seatMemberId: 'lead',
    );
    addTearDown(() async {
      await cubit.close();
      await runtime.permissionsController.close();
      await runtime.clientRequestsController.close();
    });
    stubPtyPendingDelivery();
    final ptySubmits = <String>[];

    await pumpSession(
      tester,
      session: mixedTeamSession(),
      selectedMemberId: 'lead',
      acpRuntime: cubit,
      onSubmit: (message) async {
        ptySubmits.add(message);
        return const HistoryContinueSubmitResult.failed();
      },
    );
    expect(tester.takeException(), isNull);

    await enterCompose(tester, 'ship the seat');
    await submitCompose(tester);

    expect(ptySubmits, isEmpty);
    expect(cubit.state.inTurn, isTrue);
    expect(cubit.state.messages, isNotEmpty);
  });

  testWidgets(
    'mixed ACP seat without a runtime does not deliver through PTY onSubmit',
    (tester) async {
      stubPtyPendingDelivery();
      final ptySubmits = <String>[];

      await pumpSession(
        tester,
        session: mixedTeamSession(),
        selectedMemberId: 'lead',
        onSubmit: (message) async {
          ptySubmits.add(message);
          return const HistoryContinueSubmitResult.failed();
        },
      );
      expect(tester.takeException(), isNull);

      await enterCompose(tester, 'do not inject');
      await submitCompose(tester);

      expect(ptySubmits, isEmpty);
    },
  );

  testWidgets(
    'mixed ACP seat without a runtime does not load PTY transcript history',
    (tester) async {
      final loads = <int>[];
      countPtyHistoryLoads(loads);

      await pumpSession(
        tester,
        session: mixedTeamSession(),
        selectedMemberId: 'lead',
      );
      expect(tester.takeException(), isNull);
      expect(loads, isEmpty);
      verify(() => seat.markExternalLoading()).called(greaterThan(0));
    },
  );

  testWidgets('mixed PTY seat still loads PTY transcript history', (
    tester,
  ) async {
    final loads = <int>[];
    countPtyHistoryLoads(loads);

    await pumpSession(
      tester,
      session: mixedTeamSession(),
      selectedMemberId: 'worker',
    );
    expect(tester.takeException(), isNull);
    expect(loads, isNotEmpty);
  });
}
