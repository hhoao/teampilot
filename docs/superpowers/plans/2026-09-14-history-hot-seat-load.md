# History 热标签冷加载 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 桌面启动时只冷加载「前台可见 tab + 正在运行的 session」，其余已打开 tab 延后到激活；冷加载前先取到完整会话文档，消除 stub 默认 `claude` 白解析 + 真实 CLI 重解析的双加载。

**Architecture:** 编排集中在 `SessionChatView`：`_loadHistory` 加 `isHistorySeatHot` 门控（非 hot 直接返回）、冷 seat 加载前经 `ChatCubit.hydrateSessionDocument` 取真实文档、`_loadHistory` 非 force 路径单飞；新增 `_refreshWhenHot()` 统一处理 routeActive 翻转与 running/busy 翻转的补触发。`ChatCubit.hydrateSessionDocument` 改为单飞，避免并发重复读 `session.json`。不改恢复流程、loader/seat 契约、侧栏列表加载。

**Tech Stack:** Flutter / Dart, `flutter_bloc`, `mocktail`, repo test runner `client/tool/run_tests.dart`。

**Spec:** `docs/superpowers/specs/2026-09-14-history-hot-seat-load-design.md`

## Global Constraints

- **Never run `flutter test` directly.** Inner loop: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`. Tests: `cd client && dart run tool/run_tests.dart <paths>`.
- Claiming done requires: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Diagnostics use `AppLogger` (`utils/logging/logger.dart`); no `print`.
- Do not commit unless the user explicitly asks. The "Checkpoint" steps below stage nothing and commit nothing unless instructed.
- Do not change user-facing copy; no l10n edits.
- File size soft limits (CODE_QUALITY): keep edits focused; `SessionChatView` is already oversized, so add only the minimal orchestration and prefer new small helpers/tests over growing `build()`.
- `ChatState`/`sessionActivities` key is `sessionId`; hot predicate is `isHistorySeatHot` in `client/lib/services/session/history_seat_key.dart`.

---

### Task 1: `ChatCubit.hydrateSessionDocument` 单飞

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart` (field near `:309`; method at `:1821-1842`)
- Test: `client/test/cubits/chat_cubit_test.dart` (inside existing group `ChatCubit list hydrate vs document hydrate`, `:1565`)

**Interfaces:**
- Consumes: `SessionRepository.loadSession(String workspaceId, String sessionId) → Future<AppSession?>`; `ChatCubit._dataStore`, `_emitSnapshot`, `stateSnapshot()`.
- Produces: `ChatCubit.hydrateSessionDocument(String workspaceId, String sessionId) → Future<AppSession?>` — now single-flight per session id. Return contract unchanged (full doc, or `null`).

- [ ] **Step 1: Write the failing test**

Add `import 'dart:async';` at the top of `client/test/cubits/chat_cubit_test.dart` if absent. At the end of the file (after the closing `main()` brace), add:

```dart
class _CountingSessionRepository extends SessionRepository {
  _CountingSessionRepository({
    required super.rootDir,
    required super.storage,
  });

  int loadSessionCalls = 0;
  final Completer<void> gate = Completer<void>();

  @override
  Future<AppSession?> loadSession(String workspaceId, String sessionId) async {
    loadSessionCalls++;
    await gate.future;
    return super.loadSession(workspaceId, sessionId);
  }
}
```

Then inside the `group('ChatCubit list hydrate vs document hydrate', ...)` (right after the `hydrateSessionDocument reloads from disk when marked but missing from state` test, before the group closes at `:1823`), add:

```dart
    test(
      'concurrent hydrateSessionDocument reads the document once',
      () async {
        final tmp = await Directory.systemTemp.createTemp(
          'chat_doc_single_flight_',
        );
        final repo = _CountingSessionRepository(
          rootDir: tmp.path,
          storage: testHomeStorage,
        );
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          storage: testHomeStorage,
          sessionRepository: repo,
          postFrameScheduler: postFrame.scheduler,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);

        final ws = await repo.createWorkspace([const WorkspaceFolder(path: '/p')]);
        final created = (await repo.createSession(ws.workspaceId)).session;
        await cubit.loadWorkspaceIndex(repo);
        await cubit.ensureSessionsForWorkspace(ws.workspaceId);
        expect(cubit.sessionHasDocument(created.sessionId), isFalse);

        final first = cubit.hydrateSessionDocument(
          ws.workspaceId,
          created.sessionId,
        );
        final second = cubit.hydrateSessionDocument(
          ws.workspaceId,
          created.sessionId,
        );
        repo.gate.complete();
        final results = await Future.wait([first, second]);

        expect(repo.loadSessionCalls, 1);
        expect(results[0], isNotNull);
        expect(identical(results[0], results[1]), isTrue);
        expect(cubit.sessionHasDocument(created.sessionId), isTrue);
      },
    );
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat_cubit_test.dart --plain-name "concurrent hydrateSessionDocument reads the document once"`
Expected: FAIL — `repo.loadSessionCalls` is `2` (no coalescing).

- [ ] **Step 3: Add the in-flight map field**

In `client/lib/cubits/chat_cubit.dart`, after the `_dataStore` field (`:309`), add:

```dart
  /// In-flight session-document hydrations keyed by session id. Restored open
  /// tabs and an activating History view hydrate the same document; coalesce so
  /// each `session.json` is read once.
  final Map<String, Future<AppSession?>> _documentHydrationInFlight = {};
```

- [ ] **Step 4: Rewrite `hydrateSessionDocument` as single-flight**

Replace the whole method at `:1821-1842` with:

```dart
  /// Loads and caches a session document. Concurrent callers for the same
  /// session id share one read. Returns the full document, or `null` when it
  /// cannot be loaded.
  Future<AppSession?> hydrateSessionDocument(
    String workspaceId,
    String sessionId,
  ) {
    final repo = _sessionRepository;
    final id = sessionId.trim();
    final ws = workspaceId.trim();
    if (repo == null || id.isEmpty || ws.isEmpty) {
      return Future<AppSession?>.value();
    }
    if (_dataStore.sessionHasDocument(id)) {
      final cached = state.sessions.where((s) => s.sessionId == id).firstOrNull;
      if (cached != null) return Future<AppSession?>.value(cached);
    }
    return _documentHydrationInFlight.putIfAbsent(id, () {
      final future = _loadSessionDocument(repo, ws, id);
      future.whenComplete(() {
        if (identical(_documentHydrationInFlight[id], future)) {
          _documentHydrationInFlight.remove(id);
        }
      });
      return future;
    });
  }

  Future<AppSession?> _loadSessionDocument(
    SessionRepository repo,
    String ws,
    String id,
  ) async {
    final full = await repo.loadSession(ws, id);
    if (full == null || isClosed) return null;
    _dataStore.markSessionDocument(id);
    _emitSnapshot(
      _dataStore.mergeLoadedSession(current: stateSnapshot(), session: full),
    );
    final tab = _tabStore.openTabBySessionId(id);
    if (tab != null) tab.persistedSession = full;
    return full;
  }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat_cubit_test.dart`
Expected: PASS, all `chat_cubit_test.dart` tests green.

- [ ] **Step 6: Checkpoint (no commit unless asked)**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

---

### Task 2: `SessionChatView` 冷加载热门控 + 文档优先 + 热转变补触发

**Files:**
- Modify: `client/lib/pages/chat/session_chat_view.dart` (fields near `:150-153`; `_loadHistory` `:522-559`; `didUpdateWidget` `:337-339`; BlocListener `:1307-1318`; new `_refreshWhenHot` after `_loadHistory`)
- Test: `client/test/pages/chat/session_chat_view_load_gating_test.dart` (new)

**Interfaces:**
- Consumes: `isHistorySeatHot({required bool routeActive, required bool isMemberRunning}) → bool` (`services/session/history_seat_key.dart`); `ChatCubit.sessionHasDocument(String sessionId) → bool`; `ChatCubit.hydrateSessionDocument(String workspaceId, String sessionId) → Future<AppSession?>`; `AiHistorySeat.state` (`AiHistoryState`), `.softReloadOrLoad(...)`, `.load(..., force:)`.
- Produces: `_SessionChatViewState._refreshWhenHot() → Future<void>` (private; used by didUpdateWidget + BlocListener).

- [ ] **Step 1: Write the failing tests**

Create `client/test/pages/chat/session_chat_view_load_gating_test.dart`:

```dart
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
  ChatState chatState = const ChatState();
  AiHistoryState seatState = const AiHistoryState();
  bool memberRunning = false;
  bool hasDocument = true;
  AppSession? hydratedDocument;
  AppSession session = _session('s1');

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

    chatCubit = _MockChatCubit();
    seat = _MockAiHistorySeat();
    when(() => seat.state).thenAnswer((_) => this.seatState);
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
    ).thenAnswer((_) => Future.value());

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
                      onSubmit: (_) async =>
                          const HistoryContinueSubmitResult(
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
    final loaded = verify(
      () => h.seat.softReloadOrLoad(
        session: captureAny(named: 'session'),
        memberId: any(named: 'memberId'),
        launchContext: any(named: 'launchContext'),
        team: any(named: 'team'),
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).captured.single as AppSession;
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/chat/session_chat_view_load_gating_test.dart`
Expected: FAIL — `offstage cold mount` and `activating`/`running flip` fail because the current code always calls `softReloadOrLoad` on mount; `hydrates the document` fails because `sessionHasDocument`/`hydrateSessionDocument` are never called.

- [ ] **Step 3: Add the load single-flight field**

In `client/lib/pages/chat/session_chat_view.dart`, after `_liveRefreshStartInFlight` (`:151`), add:

```dart
  /// Single-flight for the non-forced history load: mount, activation, and
  /// running/busy transitions can fire in one async window; coalesce so a cold
  /// seat is never parsed twice.
  Future<void>? _historyLoadInFlight;
```

- [ ] **Step 4: Replace `_loadHistory` with gated, document-first, single-flight implementation**

Replace the whole `_loadHistory` method at `:522-559` with:

```dart
  Future<void> _loadHistory({bool force = false}) {
    if (force) return _loadHistoryImpl(force: true);
    final inFlight = _historyLoadInFlight;
    if (inFlight != null) return inFlight;
    final future = _loadHistoryImpl(force: false);
    _historyLoadInFlight = future;
    future
        .whenComplete(() {
          if (identical(_historyLoadInFlight, future)) {
            _historyLoadInFlight = null;
          }
        })
        .ignore();
    return future;
  }

  Future<void> _loadHistoryImpl({required bool force}) async {
    final seat = _seat;
    if (seat == null) return;
    final chat = context.read<ChatCubit>();
    final running = chat.isMemberRunning(
      sessionId: widget.session.sessionId,
      memberId: _shellMemberId,
    );
    // Cold seats only load when hot (visible or running). Offstage, idle
    // restored tabs defer to first activation instead of parsing on boot.
    if (!force &&
        !isHistorySeatHot(
          routeActive: widget.routeActive,
          isMemberRunning: running,
        )) {
      appLogger.d(
        '[history-defer] not-hot skip session=${widget.session.sessionId} '
        'member=$_shellMemberId routeActive=${widget.routeActive} '
        'running=$running',
      );
      await _liveRefresh?.stop();
      return;
    }
    final ready =
        seat.state.status == AiHistoryViewStatus.ready &&
        seat.state.sessionId == widget.session.sessionId &&
        seat.state.memberId == widget.selectedMemberId;
    // A list-row stub carries no persisted CLI (resolver falls back to claude).
    // Load the session document first so the cold parse locates the real
    // transcript once instead of guessing and re-parsing.
    var session = widget.session;
    if (!ready && !chat.sessionHasDocument(session.sessionId)) {
      final hydrated = await chat.hydrateSessionDocument(
        session.workspaceId,
        session.sessionId,
      );
      if (!mounted) return;
      if (hydrated != null) session = hydrated;
    }
    if (force) {
      await seat.load(
        session: session,
        memberId: widget.selectedMemberId,
        launchContext: _launchContext,
        team: widget.team,
        workingDirectory: _workspaceRoot,
        force: true,
      );
      if (!mounted) return;
      _maybeStartLiveRefreshForRunningPty();
      _syncAwaitingFromWorkingSessions(chat.state);
      if (seat.state.awaitingAssistant) {
        unawaited(_startLiveRefresh(skipInitialRefresh: true));
      }
      return;
    }
    await seat.softReloadOrLoad(
      session: session,
      memberId: widget.selectedMemberId,
      launchContext: _launchContext,
      team: widget.team,
      workingDirectory: _workspaceRoot,
    );
    if (!mounted) return;
    _maybeStartLiveRefreshForRunningPty();
    _syncAwaitingFromWorkingSessions(chat.state);
    if (seat.state.awaitingAssistant) {
      unawaited(_startLiveRefresh(skipInitialRefresh: true));
    }
  }

  /// Single entry for "this seat's hot state may have changed": load a cold hot
  /// seat, otherwise (re)start or stop live refresh.
  Future<void> _refreshWhenHot() async {
    if (!mounted) return;
    final seat = _seat;
    final running = context.read<ChatCubit>().isMemberRunning(
      sessionId: widget.session.sessionId,
      memberId: _shellMemberId,
    );
    if (!isHistorySeatHot(
      routeActive: widget.routeActive,
      isMemberRunning: running,
    )) {
      await _liveRefresh?.stop();
      return;
    }
    final ready =
        seat != null &&
        seat.state.status == AiHistoryViewStatus.ready &&
        seat.state.sessionId == widget.session.sessionId &&
        seat.state.memberId == widget.selectedMemberId;
    if (!ready) {
      await _loadHistoryThenHydratePersistedPendingUsers();
      return;
    }
    _maybeStartLiveRefreshForRunningPty();
  }
```

- [ ] **Step 5: Wire `_refreshWhenHot` into `didUpdateWidget`**

In `didUpdateWidget`, replace the `routeActive` branch (`:337-339`):

```dart
    } else if (oldWidget.routeActive != widget.routeActive) {
      unawaited(_refreshWhenHot());
    }
```

- [ ] **Step 6: Wire `_refreshWhenHot` into the busy `BlocListener`**

Replace the `isSessionBusy` listener body (`:1311-1317`) with:

```dart
                listener: (context, state) {
                  _syncAwaitingFromWorkingSessions(state);
                  unawaited(_refreshWhenHot());
                  final chat = context.read<ChatCubit>();
                  _notifyFollowUpMemberWorking(chat);
                  _clearStoppedTurnIfSeatIdle(chat);
                },
```

- [ ] **Step 7: Run the new tests**

Run: `cd client && dart run tool/run_tests.dart test/pages/chat/session_chat_view_load_gating_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 8: Run the existing SessionChatView tests for regressions**

Run: `cd client && dart run tool/run_tests.dart test/pages/chat/session_chat_view_draft_cache_test.dart test/pages/chat/session_chat_workspace_bundle_test.dart test/cubits/ai_history_cubit_test.dart test/services/session/history_seat_key_test.dart`
Expected: PASS. Draft-cache tests mount with `routeActive:false`; they must still hydrate pending users (draft/retry flows) — the gate only skips the seat load, never `_hydratePersistedPendingUsers`.

- [ ] **Step 9: Checkpoint (no commit unless asked)**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

---

### Task 3: 收口验证

**Files:** none (verification only)

- [ ] **Step 1: Full analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: clean.

- [ ] **Step 2: Full test suite**

Run: `cd client && dart run tool/run_tests.dart`
Expected: PASS.

- [ ] **Step 3: Report**

Summarize: which tests were added, the analyze/test output, and confirm the two behaviors (offstage tabs no longer parse on boot; hot cold seats hydrate the document before parsing). Do not commit unless the user explicitly asks.
