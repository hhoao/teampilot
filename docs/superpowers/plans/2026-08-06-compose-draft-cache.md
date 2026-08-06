# Compose Draft Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cache chat compose input text in memory per workspace/session so switching away and back never loses what the user typed.

**Architecture:** A tiny app-scoped in-memory `ComposeDraftCache` service keyed by `workspaceId` (landing compose) and `sessionId` (session compose). Compose hosts restore their draft on `initState`, sync the cache on every controller change, and clear the entry once the text is consumed. Spec: `docs/superpowers/specs/2026-08-06-compose-draft-cache-design.md`.

**Tech Stack:** Flutter/Dart, `flutter_bloc`, `mocktail` for tests.

## Global Constraints

- In-memory only — no disk writes for drafts, no new dependencies.
- Empty (trimmed) text writes **remove** the cache entry.
- Ask AI (`initialText != null`) never reads or writes the landing draft.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`.
- Tests that touch `AppStorage` use `setUpTestAppStorage()` / `tearDownTestAppStorage()` from `client/test/support/post_frame_test_harness.dart`.
- No `print`; user-facing errors go through l10n; diagnostics through `AppLogger`.
- The shared instance is the module-level `final composeDraftCache`; tests reset it in `setUp` via `composeDraftCache.clear()`.

---

### Task 1: `ComposeDraftCache` service + unit tests

**Files:**
- Create: `client/lib/services/compose/compose_draft_cache.dart`
- Test: `client/test/services/compose/compose_draft_cache_test.dart`

**Interfaces:**
- Produces (used by Tasks 2–4):
  - `String? ComposeDraftCache.landingDraft(String workspaceId)`
  - `void ComposeDraftCache.setLandingDraft(String workspaceId, String text)`
  - `void ComposeDraftCache.clearLandingDraft(String workspaceId)`
  - `String? ComposeDraftCache.sessionDraft(String sessionId)`
  - `void ComposeDraftCache.setSessionDraft(String sessionId, String text)`
  - `void ComposeDraftCache.clearSessionDraft(String sessionId)`
  - `void ComposeDraftCache.clear()` (`@visibleForTesting`)
  - Module-level `final ComposeDraftCache composeDraftCache`

- [ ] **Step 1: Write the failing unit test**

Create `client/test/services/compose/compose_draft_cache_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_draft_cache.dart';

void main() {
  test('landing draft round-trips by workspaceId', () {
    final cache = ComposeDraftCache();
    expect(cache.landingDraft('w1'), isNull);

    cache.setLandingDraft('w1', 'hello');

    expect(cache.landingDraft('w1'), 'hello');
    expect(cache.landingDraft('w2'), isNull);

    cache.clearLandingDraft('w1');
    expect(cache.landingDraft('w1'), isNull);
  });

  test('session draft round-trips by sessionId', () {
    final cache = ComposeDraftCache();
    cache.setSessionDraft('s1', 'hi');
    expect(cache.sessionDraft('s1'), 'hi');
    expect(cache.sessionDraft('s2'), isNull);

    cache.clearSessionDraft('s1');
    expect(cache.sessionDraft('s1'), isNull);
  });

  test('landing and session keys are independent', () {
    final cache = ComposeDraftCache();
    cache.setLandingDraft('w1', 'landing');
    cache.setSessionDraft('s1', 'session');

    expect(cache.landingDraft('w1'), 'landing');
    expect(cache.sessionDraft('s1'), 'session');
    expect(cache.sessionDraft('w1'), isNull);

    cache.clearLandingDraft('w1');
    expect(cache.sessionDraft('s1'), 'session');
  });

  test('writing trimmed-empty text removes the entry', () {
    final cache = ComposeDraftCache();
    cache.setLandingDraft('w1', 'draft');
    cache.setLandingDraft('w1', '   ');
    expect(cache.landingDraft('w1'), isNull);

    cache.setSessionDraft('s1', 'draft');
    cache.setSessionDraft('s1', '');
    expect(cache.sessionDraft('s1'), isNull);
  });

  test('clear() resets all entries', () {
    final cache = ComposeDraftCache();
    cache.setLandingDraft('w1', 'a');
    cache.setSessionDraft('s1', 'b');
    cache.clear();
    expect(cache.landingDraft('w1'), isNull);
    expect(cache.sessionDraft('s1'), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/compose/compose_draft_cache_test.dart`
Expected: FAIL — `ComposeDraftCache` does not exist.

- [ ] **Step 3: Write the implementation**

Create `client/lib/services/compose/compose_draft_cache.dart`:

```dart
import 'package:flutter/foundation.dart';

/// In-memory cache of compose input drafts, keyed by workspace (landing
/// compose) or session (session compose). Survives compose host unmounts so
/// switching away and back does not lose typed text. Not persisted to disk.
class ComposeDraftCache {
  ComposeDraftCache({Map<String, String>? store}) : _store = store ?? {};

  final Map<String, String> _store;

  static const _landingPrefix = 'landing:';
  static const _sessionPrefix = 'session:';

  // ── Landing compose (workspace "New Chat") ──────────────────────────────

  String? landingDraft(String workspaceId) =>
      _store[_landingPrefix + workspaceId];

  void setLandingDraft(String workspaceId, String text) =>
      _set(_landingPrefix + workspaceId, text);

  void clearLandingDraft(String workspaceId) =>
      _store.remove(_landingPrefix + workspaceId);

  // ── Session compose (session workbench) ─────────────────────────────────

  String? sessionDraft(String sessionId) => _store[_sessionPrefix + sessionId];

  void setSessionDraft(String sessionId, String text) =>
      _set(_sessionPrefix + sessionId, text);

  void clearSessionDraft(String sessionId) =>
      _store.remove(_sessionPrefix + sessionId);

  /// Writing trimmed-empty text removes the entry — a cleared input must not
  /// resurrect stale text on remount.
  void _set(String key, String text) {
    if (text.trim().isEmpty) {
      _store.remove(key);
      return;
    }
    _store[key] = text;
  }

  /// Test helper / app teardown.
  @visibleForTesting
  void clear() => _store.clear();
}

/// Shared app-scoped instance. Compose hosts restore from and sync to this
/// instance directly; tests reset it via [ComposeDraftCache.clear].
final ComposeDraftCache composeDraftCache = ComposeDraftCache();
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/compose/compose_draft_cache_test.dart`
Expected: PASS (all 5 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/compose/compose_draft_cache.dart \
        client/test/services/compose/compose_draft_cache_test.dart
git commit -m "feat(compose): add in-memory compose draft cache"
```

---

### Task 2: Landing compose restore + sync

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart`
  - imports (~line 44): add the cache import
  - `initState` (~lines 182–192): restore draft + attach listener
  - add `_syncComposeDraft()` method
  - `dispose` (~lines 310–317): remove listener
- Test: `client/test/pages/home_workspace/workspace/workspace_chat_landing_draft_cache_test.dart`

**Interfaces:**
- Consumes: `composeDraftCache.landingDraft` / `setLandingDraft` (Task 1).
- Produces: behavior — landing compose restores the cached draft when `initialText == null`, syncs the cache on every change, and leaves the cache alone when `initialText != null`.

- [ ] **Step 1: Write the failing widget tests**

Create `client/test/pages/home_workspace/workspace/workspace_chat_landing_draft_cache_test.dart`. The harness mirrors `workspace_chat_landing_initial_text_test.dart`:

```dart
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
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/compose/compose_draft_cache.dart';
import 'package:teampilot/theme/app_theme.dart';

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

void main() {
  setUp(() {
    setUpTestAppStorage();
    composeDraftCache.clear();
  });
  tearDown(tearDownTestAppStorage);

  testWidgets('restores the cached landing draft on mount', (tester) async {
    composeDraftCache.setLandingDraft('workspace-1', 'my draft');
    await tester.pumpWidget(_landing(initialText: null));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'my draft');
    expect(field.controller!.selection.baseOffset, 'my draft'.length);
  });

  testWidgets('does not restore the cache when initialText is provided',
      (tester) async {
    composeDraftCache.setLandingDraft('workspace-1', 'cached');
    await tester.pumpWidget(_landing(initialText: 'prefill'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'prefill');
    // The pre-seeded cache entry is untouched by Ask AI-style mounts.
    expect(composeDraftCache.landingDraft('workspace-1'), 'cached');
  });

  testWidgets('typing writes the draft into the cache', (tester) async {
    await tester.pumpWidget(_landing(initialText: null));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'typed message');
    await tester.pump();

    expect(composeDraftCache.landingDraft('workspace-1'), 'typed message');
  });

  testWidgets('clearing the field removes the cached draft', (tester) async {
    composeDraftCache.setLandingDraft('workspace-1', 'old');
    await tester.pumpWidget(_landing(initialText: null));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();

    expect(composeDraftCache.landingDraft('workspace-1'), isNull);
  });

  testWidgets('remounting after unmount restores the typed draft',
      (tester) async {
    await tester.pumpWidget(_landing(initialText: null));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'work in progress');
    await tester.pump();

    // Simulate navigating away and back — host unmounts, then remounts.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_landing(initialText: null));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'work in progress');
  });
}

Widget _landing({required String? initialText}) {
  final workspace = Workspace(workspaceId: 'workspace-1', createdAt: 1);
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
  _stubCubit(pluginCubit, const PluginState());
  _stubCubit(sessionPreferencesCubit, SessionPreferencesState());
  _stubCubit(skillCubit, const SkillState());
  _stubCubit(worktreeCubit, const WorktreeState());
  when(() => worktreeCubit.worktreesForProject(any())).thenReturn(const []);

  final theme = buildDarkTheme();
  return MultiRepositoryProvider(
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/pages/home_workspace/workspace/workspace_chat_landing_draft_cache_test.dart`
Expected: FAIL — the restore tests see an empty field (`'my draft'` vs `''`).

- [ ] **Step 3: Implement restore + sync in `unbound_compose_body.dart`**

Add the import next to the other compose imports:

```dart
import '../../../services/compose/compose_draft_cache.dart';
```

Replace the `initState` seed block (currently lines ~182–192):

```dart
    final seed = widget.initialText;
    if (seed != null && seed.isNotEmpty) {
      _controller.value = TextEditingValue(
        text: seed,
        selection: TextSelection.collapsed(offset: seed.length),
      );
    } else if (widget.initialText == null) {
      // Restore the cached landing draft so navigating away and back does not
      // lose typed text. Ask AI (initialText != null) never reads the cache.
      final draft = composeDraftCache.landingDraft(
        widget.workspace.workspaceId,
      );
      if (draft != null && draft.isNotEmpty) {
        _controller.value = TextEditingValue(
          text: draft,
          selection: TextSelection.collapsed(offset: draft.length),
        );
      }
    }
    _controller.addListener(_syncComposeDraft);
    unawaited(_loadDraft());
```

Add the sync method (e.g., right after `initState`):

```dart
  /// Keeps [composeDraftCache] in sync with the compose field on every change
  /// (typing, voice insert, enhance). No setState — the field's own onChanged
  /// rebuilds; this fires for programmatic edits too.
  void _syncComposeDraft() {
    composeDraftCache.setLandingDraft(
      widget.workspace.workspaceId,
      _controller.text,
    );
  }
```

In `dispose`, remove the listener before disposing the controller:

```dart
  @override
  void dispose() {
    _stopVoiceSessionClock();
    _voiceInput.dispose();
    _controller.removeListener(_syncComposeDraft);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/pages/home_workspace/workspace/workspace_chat_landing_draft_cache_test.dart`
Expected: PASS (all 5).

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/unbound_compose_body.dart \
        client/test/pages/home_workspace/workspace/workspace_chat_landing_draft_cache_test.dart
git commit -m "feat(compose): persist landing compose draft across navigation"
```

---

### Task 3: Session compose restore + sync

**Files:**
- Modify: `client/lib/pages/chat/session_chat_view.dart`
  - imports (~line 48): add the cache import
  - `initState` (~lines 199–204): restore draft **before** attaching the change listener
  - `_onComposeChanged` (~lines 291–293): sync draft to cache
- Test: `client/test/pages/chat/session_chat_view_draft_cache_test.dart`

**Interfaces:**
- Consumes: `composeDraftCache.sessionDraft` / `setSessionDraft` (Task 1).
- Produces: behavior — session compose restores the cached draft on mount and syncs the cache on every change.

**Why restore before `addListener`:** setting `_controller.value` synchronously notifies listeners; `_onComposeChanged` calls `setState`, which throws during `initState`. Restoring before attaching the listener avoids the `setState`-during-mount error entirely.

- [ ] **Step 1: Write the failing widget test**

Create `client/test/pages/chat/session_chat_view_draft_cache_test.dart`. `SessionChatView` reads many cubits; every one is mocked with mocktail. The `AiHistoryCubit` is mocked at the `ensureSeat` seam — it returns a `MockAiHistorySeat` whose `state` is a default `AiHistoryState` and whose load calls are no-ops:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/ai_history_cubit.dart';
import 'package:teampilot/cubits/ai_history_seat.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/expert_hub_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/pages/chat/session_chat_view.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/compose/compose_draft_cache.dart';
import 'package:teampilot/theme/app_theme.dart';

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

void _stubCubit<TState>(Cubit<TState> cubit, TState state) {
  when(() => cubit.state).thenReturn(state);
  when(() => cubit.stream).thenAnswer((_) => Stream<TState>.empty());
}

void main() {
  late _MockAiHistorySeat seat;

  setUp(() {
    setUpTestAppStorage();
    composeDraftCache.clear();

    seat = _MockAiHistorySeat();
    when(() => seat.state).thenReturn(const AiHistoryState());
    when(() => seat.load(any(), any(), any(), any(), any(), any()))
        .thenAnswer((_) => Future.value());
    when(() => seat.softReloadOrLoad(any(), any(), any(), any(), any()))
        .thenAnswer((_) => Future.value());
  });
  tearDown(tearDownTestAppStorage);

  Future<void> pumpSession(
    WidgetTester tester, {
    required AppSession session,
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
    when(() => aiHistoryCubit.ensureSeat(any(), any())).thenReturn(seat);
    when(() => worktreeCubit.worktreesForProject(any())).thenReturn(const []);

    final theme = buildDarkTheme();
    await tester.pumpWidget(
      MultiBlocProvider(
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
          BlocProvider<AgentAttentionCubit>.value(
            value: agentAttentionCubit,
          ),
          BlocProvider<EditorCubit>.value(value: editorCubit),
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
                body: SessionChatView(
                  session: session,
                  workspace: workspace,
                  selectedMemberId: '',
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

  testWidgets('remounting after unmount restores the typed draft',
      (tester) async {
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
}
```

Note: if the full build surfaces extra cubit reads (e.g. a new `context.watch` stub), add the same `_stubCubit`/`when` pattern for that cubit.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/pages/chat/session_chat_view_draft_cache_test.dart`
Expected: FAIL — restore test sees an empty field.

- [ ] **Step 3: Implement restore + sync in `session_chat_view.dart`**

Add the import next to the other compose imports:

```dart
import '../../services/compose/compose_draft_cache.dart';
```

In `initState`, insert the restore **before** `_controller.addListener(_onComposeChanged);` (currently ~line 200):

```dart
    unawaited(_voiceInput.initialize());
    // Restore the cached session draft before attaching the change listener so
    // the restore does not notify _onComposeChanged (no setState during mount).
    final draft = composeDraftCache.sessionDraft(widget.session.sessionId);
    if (draft != null && draft.isNotEmpty) {
      _controller.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    }
    _controller.addListener(_onComposeChanged);
    _bindSeat();
    _loadHistory();
    unawaited(_loadWorkspaceProjectBundle());
```

Replace `_onComposeChanged` (currently ~lines 291–293):

```dart
  void _onComposeChanged() {
    composeDraftCache.setSessionDraft(
      widget.session.sessionId,
      _controller.text,
    );
    if (mounted) setState(() {});
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/pages/chat/session_chat_view_draft_cache_test.dart`
Expected: PASS (all 3). The restore test also proves no `setState`-during-mount error.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat/session_chat_view.dart \
        client/test/pages/chat/session_chat_view_draft_cache_test.dart
git commit -m "feat(compose): persist session compose draft across navigation"
```

---

### Task 4: Clear-on-consume wiring + lifecycle cleanup

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_pane.dart` (~lines 75–82)
- Modify: `client/lib/cubits/chat_cubit.dart`
  - imports: add the cache import
  - `deleteSession` (~line 1930): clear the session draft
  - `deleteWorkspace` (~line 2020): clear the landing draft
- Test: modify `client/test/cubits/chat_cubit_test.dart`

**Interfaces:**
- Consumes: `composeDraftCache.clearLandingDraft` / `clearSessionDraft` (Task 1).
- Produces: landing draft is cleared only when a session actually opens; session draft is cleared on session delete; landing draft is cleared on workspace delete.

- [ ] **Step 1: Write the failing tests**

In `client/test/cubits/chat_cubit_test.dart`, add the import (next to the existing imports):

```dart
import 'package:teampilot/services/compose/compose_draft_cache.dart';
```

Add a setUp that resets the shared cache (next to the existing `setUp(setUpTestAppStorage);`):

```dart
  setUp(() => composeDraftCache.clear());
```

Add two tests inside the same group as the existing `deleteSession` test (~line 713), reusing its harness helpers (`Directory.systemTemp.createTemp`, `SessionRepository`, `PostFrameTestHarness`, `_FakeTerminalSession`, `testAutomationRepository`, `_registerTempCubitCleanup`, `drainPendingAsyncWork`):

```dart
    test(
      'deleteSession clears the cached session compose draft',
      () async {
        final tmp = await Directory.systemTemp.createTemp(
          'chat_cubit_draft_clear_',
        );
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/a'),
        ]);
        final session = await repo.createSession(
          workspace.workspaceId,
          sessionTeam: '',
          rosterMembers: const [],
        );
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
          postFrameScheduler: postFrame.scheduler,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);

        await cubit.loadWorkspaceData(repo);
        composeDraftCache.setSessionDraft(session.sessionId, 'in progress');

        await cubit.deleteSession(repo, session.sessionId);
        await drainPendingAsyncWork();
        await postFrame.flush();

        expect(composeDraftCache.sessionDraft(session.sessionId), isNull);
      },
    );

    test(
      'deleteWorkspace clears the cached landing compose draft',
      () async {
        final tmp = await Directory.systemTemp.createTemp(
          'chat_cubit_workspace_draft_clear_',
        );
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/a'),
        ]);
        final postFrame = PostFrameTestHarness();
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
          terminalSessionFactory:
              ({required String executable, int scrollbackLines = 10000}) =>
                  _FakeTerminalSession(executable: executable),
          postFrameScheduler: postFrame.scheduler,
        );
        _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);

        await cubit.loadWorkspaceData(repo);
        composeDraftCache.setLandingDraft(workspace.workspaceId, 'draft');

        await cubit.deleteWorkspace(repo, workspace.workspaceId);
        await drainPendingAsyncWork();
        await postFrame.flush();

        expect(composeDraftCache.landingDraft(workspace.workspaceId), isNull);
      },
    );
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/cubits/chat_cubit_test.dart`
Expected: FAIL — cache entries still present after delete.

- [ ] **Step 3: Implement the wiring**

`client/lib/pages/home_workspace/workspace/workspace_chat_pane.dart` — add the import:

```dart
import '../../../services/compose/compose_draft_cache.dart';
```

And pass `onSessionOpened` into the existing `submitWorkspaceLandingMessage` call (~lines 75–82):

```dart
      await submitWorkspaceLandingMessage(
        context,
        workspace,
        launch: draft,
        message: message,
        workingDirectory: workingDirectory,
        expertKey: draft.expertKey,
        onSessionOpened: (_) =>
            composeDraftCache.clearLandingDraft(workspace.workspaceId),
      );
```

`client/lib/cubits/chat_cubit.dart` — add the import:

```dart
import '../services/compose/compose_draft_cache.dart';
```

In `deleteSession`, clear the draft immediately after the session lookup (before any early return):

```dart
  Future<void> deleteSession(SessionRepository repo, String sessionId) async {
    final session = state.sessions
        .where((s) => s.sessionId == sessionId)
        .firstOrNull;
    composeDraftCache.clearSessionDraft(sessionId);
    final wasActive = state.activeSessionId == sessionId;
```

In `deleteWorkspace`, clear the landing draft after the `workspace == null` guard:

```dart
    if (workspace == null) return;
    composeDraftCache.clearLandingDraft(workspaceId);
    for (final sid in workspace.sessionIds.toList()) {
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/cubits/chat_cubit_test.dart`
Expected: PASS (new tests green; existing tests still green).

- [ ] **Step 5: Full check + commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: analyze clean, all tests pass.

```bash
git add client/lib/pages/home_workspace/workspace/workspace_chat_pane.dart \
        client/lib/cubits/chat_cubit.dart \
        client/test/cubits/chat_cubit_test.dart
git commit -m "feat(compose): clear cached drafts when consumed or deleted"
```

---

## Self-review notes

- **Spec coverage:** Task 1 = cache service + empty-removal rule; Task 2 = landing restore/sync/skip-for-Ask-AI; Task 3 = session restore/sync; Task 4 = clear-on-consume (pane `onSessionOpened`) + lifecycle cleanup (`deleteSession`/`deleteWorkspace`). The spec's Ask AI exclusion is covered in Task 2; the spec's "send clears session draft automatically" is covered by Task 3's listener writing trimmed-empty → Task 1's removal rule.
- **Clear-on-open wiring testability:** the `workspace_chat_pane` `onSessionOpened` one-liner is verified by `flutter analyze` + review; the session-open path (real launch pipeline) is not unit-testable without heavy integration, so it is deliberately not given a dedicated test. All surrounding semantics (cache removal on clear, restore on mount) are covered by Tasks 1–3 and the Task 4 cubit tests.
- **Type consistency:** `landingDraft`/`setLandingDraft`/`clearLandingDraft` and `sessionDraft`/`setSessionDraft`/`clearSessionDraft` are defined once (Task 1) and used verbatim in Tasks 2–4.
