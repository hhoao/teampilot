import 'package:ai_message_core/ai_message_core.dart'
    show AiMessage, AiRole, AiTextPart, ExternalStoreAiThreadRuntime;
import 'dart:async';
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
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/pages/chat/session_chat_view.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/compose/compose_draft_cache.dart';
import 'package:teampilot/services/compose/compose_draft_store.dart';
import 'package:teampilot/services/follow_up/follow_up_queue.dart';
import 'package:teampilot/services/session/history_awaiting_working_sync.dart';
import 'package:teampilot/services/session/failed_message_store.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/theme/app_theme.dart';

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

class _FakeFailedMessageStore extends Fake implements FailedMessageStore {}

class _MockFailedMessageStore extends Mock implements FailedMessageStore {}

class _MockMemberPresenceCubit extends Mock implements MemberPresenceCubit {}

class _MockLayoutCubit extends Mock implements LayoutCubit {}

class _MockSessionLifecycleService extends Mock
    implements SessionLifecycleService {}

void _stubCubit<TState>(Cubit<TState> cubit, TState state) {
  when(() => cubit.state).thenReturn(state);
  when(() => cubit.stream).thenAnswer((_) => Stream<TState>.empty());
}

void main() {
  late _MockAiHistorySeat seat;
  late ExternalStoreAiThreadRuntime runtime;

  setUpAll(() {
    registerFallbackValue(_FakeFailedMessageStore());
    registerFallbackValue(
      FailedMessageRecord(
        id: 'fallback',
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
  });

  setUp(() {
    setUpTestAppStorage();
    AppStorage.installForTesting(
      filesystem: InMemoryFilesystem(),
      paths: const AppPaths('/compose-draft-test'),
      home: '/compose-draft-test',
      cwd: '/compose-draft-test',
    );
    composeDraftCache.clear();

    seat = _MockAiHistorySeat();
    runtime = ExternalStoreAiThreadRuntime();
    _stubCubit(seat, const AiHistoryState());
    when(() => seat.subagentAttachments).thenReturn(const {});
    when(() => seat.runtime).thenReturn(runtime);
    when(() => seat.loadedMessages).thenReturn(const []);
    when(() => seat.pendingDeliveryStatuses).thenReturn(const {});
    when(
      () => seat.hydratePendingUsers(
        store: any(named: 'store'),
        workspaceId: any(named: 'workspaceId'),
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async {});
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
        createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
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
    when(
      () => seat.retryPendingUser(
        store: any(named: 'store'),
        workspaceId: any(named: 'workspaceId'),
        sessionId: any(named: 'sessionId'),
        record: any(named: 'record'),
      ),
    ).thenAnswer((invocation) async {
      final record = invocation.namedArguments[#record] as FailedMessageRecord;
      return record.copyWith(status: FailedMessageStatus.sending);
    });
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

  Future<void> pumpSession(
    WidgetTester tester, {
    required AppSession session,
    Future<HistoryContinueSubmitResult> Function(String)? onSubmit,
    FailedMessageStore? failedMessageStore,
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
    when(
      () => lifecycle.launchWorkTarget(any(), memberId: any(named: 'memberId')),
    ).thenReturn(RuntimeTarget.local());

    _stubCubit(chatCubit, ChatState(workspaces: [workspace]));
    _stubCubit(aiHistoryCubit, const AiHistoryState());
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
    when(() => chatCubit.isMemberWorking(any(), any())).thenReturn(false);
    when(
      () => chatCubit.isMemberRunning(
        sessionId: any(named: 'sessionId'),
        memberId: any(named: 'memberId'),
      ),
    ).thenReturn(false);
    when(() => chatCubit.lifecycle).thenReturn(lifecycle);
    when(
      () => chatCubit.followUpQueue,
    ).thenReturn(InMemoryFollowUpQueueStore());
    when(() => chatCubit.tabStore).thenReturn(ChatTabStore());
    when(
      () => aiHistoryCubit.ensureSeat(
        sessionId: any(named: 'sessionId'),
        selectedMemberId: any(named: 'selectedMemberId'),
      ),
    ).thenReturn(seat);
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
                    selectedMemberId: '',
                    onSubmit:
                        onSubmit ??
                        (_) async => const HistoryContinueSubmitResult(
                          ok: true,
                          channel: HistoryContinueChannel.pty,
                        ),
                    failedMessageStore: failedMessageStore,
                    routeActive: false,
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

  testWidgets('restores the cached session draft on mount', (tester) async {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'ws-1',
      folders: const [WorkspaceFolder(path: '/work')],
      cli: CliTool.claude,
      createdAt: 1,
    );
    composeDraftCache.setSessionDraft('s1', 'continue this');

    await pumpSession(tester, session: session);

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'continue this');
  });

  testWidgets('session restores persisted draft after cache reset', (
    tester,
  ) async {
    await tester.runAsync(
      () => ComposeDraftStore(
        fs: AppStorage.fs,
        rootPath: AppStorage.appDataRoot,
      ).saveSession('ws-1', 's1', 'retry after restart'),
    );
    composeDraftCache.clear();

    await pumpSession(
      tester,
      session: AppSession(
        sessionId: 's1',
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: '/work')],
        cli: CliTool.claude,
        createdAt: 1,
      ),
    );
    await _flushRealIo(tester);

    expect(_composeField(tester).controller!.text, 'retry after restart');
  });

  testWidgets('typing writes the draft into the cache', (tester) async {
    final session = AppSession(
      sessionId: 's2',
      workspaceId: 'ws-1',
      folders: const [WorkspaceFolder(path: '/work')],
      cli: CliTool.claude,
      createdAt: 1,
    );

    await pumpSession(tester, session: session);
    await tester.enterText(find.byType(TextField).first, 'draft two');
    await tester.pump();

    expect(composeDraftCache.sessionDraft('s2'), 'draft two');
  });

  testWidgets('remounting after unmount restores the typed draft', (
    tester,
  ) async {
    final session = AppSession(
      sessionId: 's3',
      workspaceId: 'ws-1',
      folders: const [WorkspaceFolder(path: '/work')],
      cli: CliTool.claude,
      createdAt: 1,
    );

    await pumpSession(tester, session: session);
    await tester.enterText(find.byType(TextField).first, 'keep me');
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpSession(tester, session: session);
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'keep me');
  });

  testWidgets('failed session delivery retains the persisted draft', (
    tester,
  ) async {
    final session = _session('s4');
    await pumpSession(
      tester,
      session: session,
      onSubmit: (_) async => const HistoryContinueSubmitResult.failed(),
    );

    await tester.enterText(find.byType(TextField).first, 'do not lose this');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(
      await ComposeDraftStore(
        fs: AppStorage.fs,
        rootPath: AppStorage.appDataRoot,
      ).loadSession('ws-1', 's4'),
      'do not lose this',
    );
  });

  testWidgets('successful session delivery removes the persisted draft', (
    tester,
  ) async {
    final session = _session('s5');
    await pumpSession(
      tester,
      session: session,
      onSubmit: (_) async => const HistoryContinueSubmitResult(
        ok: true,
        channel: HistoryContinueChannel.pty,
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'delivered');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(
      await ComposeDraftStore(
        fs: AppStorage.fs,
        rootPath: AppStorage.appDataRoot,
      ).loadSession('ws-1', 's5'),
      isNull,
    );
  });

  testWidgets('Retry redelivers a failed bubble through the session callback', (
    tester,
  ) async {
    final store = FailedMessageStore(
      fs: AppStorage.fs,
      rootPath: AppStorage.appDataRoot,
    );
    final record = FailedMessageRecord(
      id: 'pending:retry',
      text: 'retry this',
      createdAt: DateTime.utc(2026),
      status: FailedMessageStatus.failed,
    );
    await store.save('ws-1', 'retry-success', record);
    runtime.setMessages([
      const AiMessage(
        id: 'pending:retry',
        role: AiRole.user,
        parts: [AiTextPart(text: 'retry this')],
      ),
    ]);
    when(
      () => seat.pendingDeliveryStatuses,
    ).thenReturn(const {'pending:retry': FailedMessageStatus.failed});
    var submitted = 0;

    await pumpSession(
      tester,
      session: _session('retry-success'),
      failedMessageStore: store,
      onSubmit: (text) async {
        submitted++;
        expect(text, 'retry this');
        return const HistoryContinueSubmitResult(
          ok: true,
          channel: HistoryContinueChannel.pty,
        );
      },
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(submitted, 1);
    verify(
      () => seat.retryPendingUser(
        store: store,
        workspaceId: 'ws-1',
        sessionId: 'retry-success',
        record: record,
      ),
    ).called(1);
  });

  testWidgets('Retry preserves a failed record when redelivery fails', (
    tester,
  ) async {
    final store = FailedMessageStore(
      fs: AppStorage.fs,
      rootPath: AppStorage.appDataRoot,
    );
    final record = FailedMessageRecord(
      id: 'pending:retry-failure',
      text: 'retry this',
      createdAt: DateTime.utc(2026),
      status: FailedMessageStatus.failed,
    );
    await store.save('ws-1', 'retry-failure', record);
    runtime.setMessages([
      const AiMessage(
        id: 'pending:retry-failure',
        role: AiRole.user,
        parts: [AiTextPart(text: 'retry this')],
      ),
    ]);
    when(
      () => seat.pendingDeliveryStatuses,
    ).thenReturn(const {'pending:retry-failure': FailedMessageStatus.failed});

    await pumpSession(
      tester,
      session: _session('retry-failure'),
      failedMessageStore: store,
      onSubmit: (_) async => const HistoryContinueSubmitResult.failed(),
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    verify(
      () => seat.markPendingFailed(
        store: store,
        workspaceId: 'ws-1',
        sessionId: 'retry-failure',
        record: record.copyWith(status: FailedMessageStatus.sending),
      ),
    ).called(1);
  });

  testWidgets('rapid Retry taps deliver only once without restoring failure', (
    tester,
  ) async {
    final store = _MockFailedMessageStore();
    final record = FailedMessageRecord(
      id: 'pending:rapid-retry',
      text: 'retry this once',
      createdAt: DateTime.utc(2026),
      status: FailedMessageStatus.failed,
    );
    final recordsReady = Completer<List<FailedMessageRecord>>();
    when(
      () => store.load('ws-1', 'rapid-retry'),
    ).thenAnswer((_) => recordsReady.future);
    runtime.setMessages([
      const AiMessage(
        id: 'pending:rapid-retry',
        role: AiRole.user,
        parts: [AiTextPart(text: 'retry this once')],
      ),
    ]);
    when(
      () => seat.pendingDeliveryStatuses,
    ).thenReturn(const {'pending:rapid-retry': FailedMessageStatus.failed});
    final delivery = Completer<HistoryContinueSubmitResult>();
    var submitted = 0;

    await pumpSession(
      tester,
      session: _session('rapid-retry'),
      failedMessageStore: store,
      onSubmit: (_) {
        submitted++;
        return delivery.future;
      },
    );

    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    recordsReady.complete([record]);
    await tester.pump();

    expect(submitted, 1);
    delivery.complete(
      const HistoryContinueSubmitResult(
        ok: true,
        channel: HistoryContinueChannel.pty,
      ),
    );
    await tester.pumpAndSettle();

    verify(
      () => seat.retryPendingUser(
        store: store,
        workspaceId: 'ws-1',
        sessionId: 'rapid-retry',
        record: record,
      ),
    ).called(1);
    verifyNever(
      () => seat.markPendingFailed(
        store: any(named: 'store'),
        workspaceId: any(named: 'workspaceId'),
        sessionId: any(named: 'sessionId'),
        record: any(named: 'record'),
      ),
    );
  });

  testWidgets('Edit and retry loads the failed text into the composer', (
    tester,
  ) async {
    final store = FailedMessageStore(
      fs: AppStorage.fs,
      rootPath: AppStorage.appDataRoot,
    );
    final record = FailedMessageRecord(
      id: 'pending:edit',
      text: 'edit this first',
      createdAt: DateTime.utc(2026),
      status: FailedMessageStatus.failed,
    );
    await store.save('ws-1', 'edit-retry', record);
    runtime.setMessages([
      const AiMessage(
        id: 'pending:edit',
        role: AiRole.user,
        parts: [AiTextPart(text: 'edit this first')],
      ),
    ]);
    when(
      () => seat.pendingDeliveryStatuses,
    ).thenReturn(const {'pending:edit': FailedMessageStatus.failed});

    await pumpSession(
      tester,
      session: _session('edit-retry'),
      failedMessageStore: store,
    );

    await tester.tap(find.text('Edit and retry'));
    await tester.pumpAndSettle();

    expect(_composeField(tester).controller!.text, 'edit this first');
  });
}

AppSession _session(String sessionId) => AppSession(
  sessionId: sessionId,
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/work')],
  cli: CliTool.claude,
  createdAt: 1,
);

TextField _composeField(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).first);

Future<void> _flushRealIo(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();
  }
}
