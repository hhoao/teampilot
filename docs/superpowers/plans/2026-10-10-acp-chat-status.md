# ACP Chat Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the ACP chat footer report what the agent is doing (启动中 / 思考中 / 生成中 / 执行工具中) instead of showing 启动中 for the whole session, and stop the empty-history pane from flashing on the first send.

**Architecture:** `AcpChatRuntimeCubit` gains an explicit `AcpChatActivity` field that is the single source of truth for turn activity, and emits the `working` attention edge it was missing. The chat message area resolves the footer chrome from that cubit (via `SessionHistoryLiveChromeX.resolveAcp`) when an ACP runtime is attached; the PTY path is untouched. The empty-pane flash is fixed by publishing the user message before awaiting the draft discard, plus a `_showThread` guard.

**Tech Stack:** Flutter / Dart, `flutter_bloc` cubits, ARB-based l10n, `moc`kito-style fakes in tests.

**Spec:** `docs/superpowers/specs/2026-10-10-acp-chat-status-design.md`

## Global Constraints

- **Never invoke `flutter test` directly.** Always `cd client && dart run tool/run_tests.dart <paths/options>`; concurrent direct runs corrupt the shared build cache.
- Test loop: inner = `flutter analyze`; verify with one test file at a time (`--plain-name` to narrow); full suite once before claiming done, in the background.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- **l10n:** edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only; regenerate with `cd client && flutter gen-l10n` (never hand-edit `app_localizations*.dart`).
- The PTY chrome path (`SessionHistoryLiveChromeX.resolve`) must not change behavior — existing PTY tests pass unmodified.
- Logging: diagnostics via `AppLogger`, never `print`. User-facing errors via l10n.
- Every commit message ends with `Co-Authored-By: Claude <noreply@anthropic.com>`.

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` | ACP turn lifecycle + transcript. Owns `AcpChatActivity`. | Modify |
| `client/lib/pages/chat/session_history_live_chrome.dart` | Footer chrome vocabulary + resolvers (PTY and ACP). | Modify |
| `client/lib/pages/chat/session_history_thread.dart` | Renders the footer row + its label. | Modify |
| `client/lib/pages/chat/session_chat_message_area.dart` | Picks the resolver (ACP vs PTY) and builds the review widget. | Modify |
| `client/lib/pages/chat/session_history_review_messages.dart` | Empty/loading/error/thread switch. | Modify |
| `client/lib/pages/chat/session_chat_view.dart` | ACP submit path; passes the runtime down. | Modify |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | Three new labels. | Modify |
| `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart` | Activity + attention unit tests. | Modify |
| `client/test/pages/chat/session_history_live_chrome_test.dart` | `resolveAcp` unit tests. | Modify |
| `client/test/pages/chat/session_history_review_messages_test.dart` | Empty-guard widget test. | Modify |
| `client/test/pages/chat/session_chat_view_acp_test.dart` | ACP footer widget test. | Modify |

---

### Task 1: `AcpChatActivity` turn-activity model

**Files:**
- Modify: `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart`
- Test: `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `enum AcpChatActivity { none, thinking, generating, toolRunning }`; `AcpChatRuntimeState.activity` (field + `copyWith` parameter, default `AcpChatActivity.none`). Task 3 and Task 4 read `state.activity`.

- [ ] **Step 1: Write the failing tests**

Append to `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`, inside `main()` after the existing `'tool call update → tool card part with status lifecycle'` test:

```dart
  test('activity walks thinking → generating → toolRunning → generating → none', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    expect(cubit.state.activity, AcpChatActivity.none);

    cubit.sendPrompt('hi');
    expect(cubit.state.activity, AcpChatActivity.thinking);

    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'he',
        isThought: false,
      ),
    );
    await pumpEventQueue();
    expect(cubit.state.activity, AcpChatActivity.generating);

    runtime.emit(
      const AcpToolCallUpdate(
        toolCallId: 't1',
        title: 'read file',
        status: AcpToolCallStatus.inProgress,
      ),
    );
    await pumpEventQueue();
    expect(cubit.state.activity, AcpChatActivity.toolRunning);

    runtime.emit(
      const AcpToolCallUpdate(
        toolCallId: 't1',
        status: AcpToolCallStatus.completed,
      ),
    );
    await pumpEventQueue();
    expect(cubit.state.activity, AcpChatActivity.generating);

    runtime.emit(const AcpStop(kind: AcpStopKind.endTurn));
    await pumpEventQueue();
    expect(cubit.state.activity, AcpChatActivity.none);
    await cubit.close();
  });

  test('two overlapping tool calls keep toolRunning until both end', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    cubit.sendPrompt('go');
    runtime.emit(
      const AcpToolCallUpdate(
        toolCallId: 't1',
        status: AcpToolCallStatus.inProgress,
      ),
    );
    runtime.emit(
      const AcpToolCallUpdate(
        toolCallId: 't2',
        status: AcpToolCallStatus.pending,
      ),
    );
    await pumpEventQueue();
    expect(cubit.state.activity, AcpChatActivity.toolRunning);

    runtime.emit(
      const AcpToolCallUpdate(
        toolCallId: 't1',
        status: AcpToolCallStatus.completed,
      ),
    );
    await pumpEventQueue();
    expect(cubit.state.activity, AcpChatActivity.toolRunning);

    runtime.emit(
      const AcpToolCallUpdate(
        toolCallId: 't2',
        status: AcpToolCallStatus.failed,
      ),
    );
    await pumpEventQueue();
    // Neither tool terminated the turn, and no chunk has arrived: back to the
    // pre-first-token state.
    expect(cubit.state.activity, AcpChatActivity.thinking);
    await cubit.close();
  });

  test('a chunk with no visible text still moves thinking → generating', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    cubit.sendPrompt('go');
    expect(cubit.state.activity, AcpChatActivity.thinking);

    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: '',
        isThought: false,
      ),
    );
    await pumpEventQueue();
    expect(cubit.state.activity, AcpChatActivity.generating);
    // Only the user bubble exists — the empty chunk added no message.
    expect(cubit.state.messages, hasLength(1));
    await cubit.close();
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`
Expected: FAIL — `The getter 'activity' isn't defined for the class 'AcpChatRuntimeState'`.

- [ ] **Step 3: Add the enum and state field**

In `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart`, add after the `AcpChatPhase` enum (which ends at line 32):

```dart
/// What the agent is doing inside the current turn.
///
/// [none] means no turn is in flight. When several signals are live at once
/// the precedence is [toolRunning] > [generating] > [thinking].
enum AcpChatActivity { none, thinking, generating, toolRunning }
```

In `AcpChatRuntimeState`, add the field and the `copyWith` parameter:

```dart
  const AcpChatRuntimeState({
    this.phase = AcpChatPhase.launching,
    this.messages = const [],
    this.inTurn = false,
    this.pendingPermission,
    this.error,
    this.activity = AcpChatActivity.none,
  });
```

```dart
  /// What the agent is doing inside the current turn.
  final AcpChatActivity activity;

  AcpChatRuntimeState copyWith({
    AcpChatPhase? phase,
    List<AiMessage>? messages,
    bool? inTurn,
    Object? pendingPermission = _unset,
    AcpChatError? error,
    bool clearError = false,
    AcpChatActivity? activity,
  }) => AcpChatRuntimeState(
    phase: phase ?? this.phase,
    messages: messages ?? this.messages,
    inTurn: inTurn ?? this.inTurn,
    pendingPermission: identical(pendingPermission, _unset)
        ? this.pendingPermission
        : pendingPermission as AgentPermissionRequest?,
    error: clearError ? null : (error ?? this.error),
    activity: activity ?? this.activity,
  );
```

- [ ] **Step 4: Add the per-turn trackers and helpers to the cubit**

In `AcpChatRuntimeCubit`, next to the existing `String? _queuedPrompt;` field:

```dart
  /// Tool-call ids opened this turn and not yet terminated.
  final Set<String> _runningToolCalls = {};

  /// Whether the current turn has emitted any message chunk yet.
  bool _seenChunkThisTurn = false;

  /// Activity implied by the turn trackers. Callers must have already updated
  /// the trackers for the event in hand.
  AcpChatActivity _turnActivity() {
    if (_runningToolCalls.isNotEmpty) return AcpChatActivity.toolRunning;
    if (_seenChunkThisTurn) return AcpChatActivity.generating;
    return AcpChatActivity.thinking;
  }

  /// Clears the per-turn trackers. Called when a turn opens and when it ends.
  void _resetTurnTrackers() {
    _seenChunkThisTurn = false;
    _runningToolCalls.clear();
  }
```

- [ ] **Step 5: Set `thinking` when a turn opens**

In `sendPrompt`, replace the queue branch:

```dart
    if (state.phase == AcpChatPhase.launching || !_runtime.isStarted) {
      _queuedPrompt = trimmed;
      _showUserMessage(trimmed);
      _resetTurnTrackers();
      emit(state.copyWith(inTurn: true, activity: AcpChatActivity.thinking));
      return true;
    }
```

In `_dispatchPrompt`, replace the first two lines:

```dart
  void _dispatchPrompt(String trimmed) {
    _showUserMessage(trimmed);
    _resetTurnTrackers();
    emit(state.copyWith(inTurn: true, activity: AcpChatActivity.thinking));
    unawaited(
```

- [ ] **Step 6: Move to `generating` on chunks**

In `_onUpdate`, in the `AcpMessageChunk()` case, set the latch before appending:

```dart
      case AcpMessageChunk():
        await _transcript?.recordChunk(update);
        if (isClosed) return;
        _removeAuthNoticeMessage();
        _seenChunkThisTurn = true;
        _appendMessageParts(_chunkParts(update));
```

Replace the whole `_appendMessageParts` method with this version (it now always re-emits the derived activity, so a chunk with no visible text still advances the status):

```dart
  /// Appends parts onto the tip assistant message (streaming continuation),
  /// or opens a new assistant message when the tip is not appendable.
  ///
  /// Consecutive [AiTextPart] / [AiReasoningPart] of the same type are
  /// concatenated. ACP streams one NDJSON chunk per token; appending each as
  /// its own part makes the UI render hundreds of thinking-process steps.
  ///
  /// Always re-emits the derived turn activity: a chunk that carries no
  /// visible text is dropped as an empty stream part but must still move the
  /// status from thinking to generating.
  void _appendMessageParts(List<AiMessagePart> parts) {
    final incoming = [
      for (final part in parts)
        if (!_isEmptyStreamPart(part)) part,
    ];
    final activity = _turnActivity();
    if (incoming.isEmpty) {
      if (activity == state.activity) return;
      emit(state.copyWith(activity: activity));
      return;
    }
    final messages = [...state.messages];
    if (messages.isNotEmpty && messages.last.role == AiRole.assistant) {
      final tip = messages.last;
      messages[messages.length - 1] = tip.copyWith(
        parts: _coalesceStreamingParts(tip.parts, incoming),
      );
    } else {
      messages.add(
        AiMessage(
          id: 'acp-a-${_uuid.v4()}',
          role: AiRole.assistant,
          parts: _coalesceStreamingParts(const [], incoming),
          createdAt: DateTime.now(),
        ),
      );
    }
    emit(state.copyWith(messages: messages, activity: activity));
  }
```

- [ ] **Step 7: Track tool calls**

In `_applyToolCall`, add the tracker update as the first statement and carry `activity` through every emit:

```dart
  void _applyToolCall(AcpToolCallUpdate update) {
    switch (update.status) {
      case AcpToolCallStatus.pending:
      case AcpToolCallStatus.inProgress:
        _runningToolCalls.add(update.toolCallId);
      case AcpToolCallStatus.completed:
      case AcpToolCallStatus.failed:
        _runningToolCalls.remove(update.toolCallId);
      case null:
        break;
    }
    final activity = _turnActivity();
    // Upsert onto the last assistant message's matching tool part; a new
    // toolCallId appends a fresh part (tool card).
    final messages = [...state.messages];
```

Then in the three emit sites inside that method, pass the activity:

- `emit(state.copyWith(messages: messages));` (matched branch) → `emit(state.copyWith(messages: messages, activity: activity));`
- `emit(state.copyWith(messages: messages));` (append branch) → `emit(state.copyWith(messages: messages, activity: activity));`
- the trailing `_appendMessageParts([...])` call is unchanged — it recomputes the same value from the trackers.

- [ ] **Step 8: Return to `none` when the turn ends**

Replace `_endTurn` and update `_endWith`:

```dart
  void _endTurn() {
    if (isClosed) return;
    _resetTurnTrackers();
    _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.done));
    emit(
      state.copyWith(
        inTurn: false,
        phase: AcpChatPhase.idle,
        pendingPermission: null,
        activity: AcpChatActivity.none,
      ),
    );
  }
```

In `_endWith`, add `_resetTurnTrackers();` next to `_queuedPrompt = null;` and add `activity: AcpChatActivity.none,` to its final `emit`.

- [ ] **Step 9: Run the tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`
Expected: PASS (all pre-existing tests in the file still pass).

- [ ] **Step 10: Commit**

```bash
git add client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart
git commit -m "feat(acp): track turn activity in the chat runtime cubit

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Emit the `working` attention edge on dispatch

**Files:**
- Modify: `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart`
- Test: `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

**Interfaces:**
- Consumes: `_applyAttention` (existing private helper), `AgentSeatAttention.working`.
- Produces: no new API — the cubit now emits attention `working` for the duration of a turn.

- [ ] **Step 1: Write the failing test**

Append to `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`:

```dart
  test('dispatch marks attention working; stop marks it done', () async {
    final attention = AgentAttentionCubit(pruneInterval: null);
    final cubit = bootCubit(attention: attention);
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    expect(
      attention.state.attentionFor(sessionId: 's1', memberId: 'acp'),
      AgentSeatAttention.done,
    );

    cubit.sendPrompt('do work');
    await pumpEventQueue();
    expect(
      attention.state.attentionFor(sessionId: 's1', memberId: 'acp'),
      AgentSeatAttention.working,
    );

    runtime.emit(const AcpStop(kind: AcpStopKind.endTurn));
    await pumpEventQueue();
    expect(
      attention.state.attentionFor(sessionId: 's1', memberId: 'acp'),
      AgentSeatAttention.done,
    );
    await cubit.close();
    await attention.close();
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart --plain-name "dispatch marks attention working"`
Expected: FAIL — expected `AgentSeatAttention.working`, actual `AgentSeatAttention.done`.

- [ ] **Step 3: Emit the edge**

In `_dispatchPrompt`, add the attention call directly after the activity emit from Task 1:

```dart
  void _dispatchPrompt(String trimmed) {
    _showUserMessage(trimmed);
    _resetTurnTrackers();
    emit(state.copyWith(inTurn: true, activity: AcpChatActivity.thinking));
    // A turn is in flight: without this the ACP seat sits at `done` for the
    // whole turn and every attention-driven surface reads "starting".
    _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.working));
    unawaited(
```

Do **not** add it to the `sendPrompt` queue branch — a queued prompt is not executing yet, and `_dispatchPrompt` fires when the queue flushes.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart
git commit -m "fix(acp): mark attention working for the duration of a turn

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Chrome vocabulary, ACP resolver, and labels

**Files:**
- Modify: `client/lib/pages/chat/session_history_live_chrome.dart`
- Modify: `client/lib/pages/chat/session_history_thread.dart:737-742`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/chat/session_history_live_chrome_test.dart`

**Interfaces:**
- Consumes: `AcpChatPhase`, `AcpChatActivity` from Task 1.
- Produces: `SessionHistoryLiveChrome.thinking | .generating | .toolRunning`; `SessionHistoryLiveChromeX.resolveAcp({required bool turnInFlight, required AcpChatPhase phase, required AcpChatActivity activity})`. Task 4 calls `resolveAcp`.

- [ ] **Step 1: Write the failing tests**

Append to `client/test/pages/chat/session_history_live_chrome_test.dart`. Add these imports at the top of the file:

```dart
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
```

and this group at the end of `main()`:

```dart
  group('SessionHistoryLiveChromeX.resolveAcp', () {
    test('none when the turn is not in flight', () {
      expect(
        SessionHistoryLiveChromeX.resolveAcp(
          turnInFlight: false,
          phase: AcpChatPhase.idle,
          activity: AcpChatActivity.none,
        ),
        SessionHistoryLiveChrome.none,
      );
    });

    test('starting while the agent is still launching', () {
      expect(
        SessionHistoryLiveChromeX.resolveAcp(
          turnInFlight: true,
          phase: AcpChatPhase.launching,
          activity: AcpChatActivity.thinking,
        ),
        SessionHistoryLiveChrome.starting,
      );
    });

    test('thinking before the first chunk', () {
      expect(
        SessionHistoryLiveChromeX.resolveAcp(
          turnInFlight: true,
          phase: AcpChatPhase.ready,
          activity: AcpChatActivity.thinking,
        ),
        SessionHistoryLiveChrome.thinking,
      );
    });

    test('generating while chunks stream', () {
      expect(
        SessionHistoryLiveChromeX.resolveAcp(
          turnInFlight: true,
          phase: AcpChatPhase.ready,
          activity: AcpChatActivity.generating,
        ),
        SessionHistoryLiveChrome.generating,
      );
    });

    test('toolRunning while a tool call is open', () {
      expect(
        SessionHistoryLiveChromeX.resolveAcp(
          turnInFlight: true,
          phase: AcpChatPhase.ready,
          activity: AcpChatActivity.toolRunning,
        ),
        SessionHistoryLiveChrome.toolRunning,
      );
    });

    test('none between turns', () {
      expect(
        SessionHistoryLiveChromeX.resolveAcp(
          turnInFlight: true,
          phase: AcpChatPhase.idle,
          activity: AcpChatActivity.none,
        ),
        SessionHistoryLiveChrome.none,
      );
    });

    test('none for an ended session', () {
      expect(
        SessionHistoryLiveChromeX.resolveAcp(
          turnInFlight: false,
          phase: AcpChatPhase.ended,
          activity: AcpChatActivity.none,
        ),
        SessionHistoryLiveChrome.none,
      );
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/chat/session_history_live_chrome_test.dart`
Expected: FAIL — `The method 'resolveAcp' isn't defined` / `'thinking' isn't defined for the class 'SessionHistoryLiveChrome'`.

- [ ] **Step 3: Extend the enum**

In `client/lib/pages/chat/session_history_live_chrome.dart`, add a relative import for the cubit at the top:

```dart
import '../../cubits/session/acp/acp_chat_runtime_cubit.dart';
```

Extend the enum:

```dart
enum SessionHistoryLiveChrome {
  /// No footer.
  none,

  /// Optimistic bubble is up but the seat PTY is not ready yet (connect /
  /// landing deliver). Label: starting.
  starting,

  /// Seat is up / working; waiting on the assistant turn. Label: running.
  running,

  /// ACP: a prompt is in flight and no chunk has arrived yet. Label: thinking.
  thinking,

  /// ACP: the agent is streaming reply or reasoning text. Label: generating.
  generating,

  /// ACP: the agent has at least one tool call in progress. Label: toolRunning.
  toolRunning,
}
```

- [ ] **Step 4: Add the resolver**

In the same file, inside `extension SessionHistoryLiveChromeX on SessionHistoryLiveChrome`, after `resolve`:

```dart
  /// Resolve the chat tip chrome for a terminal-less ACP session.
  ///
  /// Mirrors [resolve]'s contract ([turnInFlight] false ⇒ [none]) and takes
  /// the cubit's phase/activity in place of the PTY signals. `phase ==
  /// launching` wins over activity: a prompt queued during launch has not
  /// started answering yet. No `ended` arm is needed — an ended session has
  /// `inTurn == false`, so [turnInFlight] is already false and the footer is
  /// never rendered.
  static SessionHistoryLiveChrome resolveAcp({
    required bool turnInFlight,
    required AcpChatPhase phase,
    required AcpChatActivity activity,
  }) {
    if (!turnInFlight) return SessionHistoryLiveChrome.none;
    if (phase == AcpChatPhase.launching) {
      return SessionHistoryLiveChrome.starting;
    }
    return switch (activity) {
      AcpChatActivity.thinking => SessionHistoryLiveChrome.thinking,
      AcpChatActivity.generating => SessionHistoryLiveChrome.generating,
      AcpChatActivity.toolRunning => SessionHistoryLiveChrome.toolRunning,
      AcpChatActivity.none => SessionHistoryLiveChrome.none,
    };
  }
```

- [ ] **Step 5: Add the labels**

In `client/lib/l10n/app_en.arb`, directly after the `"sessionHistoryRunning": "Running…",` line (line 800):

```json
  "sessionHistoryThinking": "Thinking…",
  "sessionHistoryGenerating": "Generating…",
  "sessionHistoryToolRunning": "Running a tool…",
```

In `client/lib/l10n/app_zh.arb`, directly after the `"sessionHistoryRunning": "运行中…",` line (line 750):

```json
  "sessionHistoryThinking": "思考中…",
  "sessionHistoryGenerating": "生成中…",
  "sessionHistoryToolRunning": "执行工具中…",
```

- [ ] **Step 6: Regenerate localizations**

Run: `cd client && flutter gen-l10n`
Expected: `app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_zh.dart` gain the three getters; no errors.

- [ ] **Step 7: Render the new labels**

In `client/lib/pages/chat/session_history_thread.dart`, replace the label switch in `_buildRunningInMessage`:

```dart
    final label = switch (widget.liveChrome) {
      SessionHistoryLiveChrome.starting => context.l10n.sessionHistoryStarting,
      SessionHistoryLiveChrome.thinking => context.l10n.sessionHistoryThinking,
      SessionHistoryLiveChrome.generating =>
        context.l10n.sessionHistoryGenerating,
      SessionHistoryLiveChrome.toolRunning =>
        context.l10n.sessionHistoryToolRunning,
      SessionHistoryLiveChrome.running ||
      SessionHistoryLiveChrome.none => context.l10n.sessionHistoryRunning,
    };
```

- [ ] **Step 8: Run the tests and analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart test/pages/chat/session_history_live_chrome_test.dart test/pages/chat/session_history_thread_test.dart`
Expected: analyze clean; both test files PASS.

- [ ] **Step 9: Commit**

```bash
git add client/lib/pages/chat/session_history_live_chrome.dart client/lib/pages/chat/session_history_thread.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/test/pages/chat/session_history_live_chrome_test.dart
git commit -m "feat(acp): add thinking/generating/toolRunning chat chrome

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Resolve the ACP footer from the cubit

**Files:**
- Modify: `client/lib/pages/chat/session_chat_message_area.dart` (constructor, the `Builder` at ~line 259, the call site at ~line 1690 of `session_chat_view.dart`)
- Modify: `client/lib/pages/chat/session_chat_view.dart:1690`
- Test: `client/test/pages/chat/session_chat_view_acp_test.dart`

**Interfaces:**
- Consumes: `SessionHistoryLiveChromeX.resolveAcp` (Task 3), `AcpChatRuntimeState.phase/activity` (Task 1).
- Produces: `SessionChatMessageArea.acpRuntime` (optional `AcpChatRuntimeCubit?`).

- [ ] **Step 1: Write the failing test**

Append to `client/test/pages/chat/session_chat_view_acp_test.dart`, inside `main()` after the Stop test:

```dart
  testWidgets('ACP generating turn shows the generating footer, not starting', (
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
    });

    await tester.runAsync(() async {
      await cubit.start(
        executable: 'gemini',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
      cubit.sendPrompt('do work');
      await Future<void>.delayed(Duration.zero);
    });
    await pumpSession(tester, session: session('s1'), acpRuntime: cubit);
    await tester.pumpAndSettle();
    expect(find.text('Thinking…'), findsOneWidget);

    await tester.runAsync(() async {
      runtime.emit(
        const AcpMessageChunk(
          role: AcpRole.assistant,
          content: 'working on it',
          isThought: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(find.text('Generating…'), findsOneWidget);
    expect(find.text('Starting…'), findsNothing);
  });
```

Add these imports to that test file if they are not already present:

```dart
import 'package:teampilot/services/acp/acp_session.dart';
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/chat/session_chat_view_acp_test.dart --plain-name "ACP generating turn"`
Expected: FAIL — `find.text('Generating…')` finds nothing (the footer currently reads `Starting…`).

- [ ] **Step 3: Thread the runtime into the message area**

In `client/lib/pages/chat/session_chat_message_area.dart`, add the import:

```dart
import '../../cubits/session/acp/acp_chat_runtime_cubit.dart';
```

Add the constructor parameter and field (place the parameter after `this.userStoppedTurn = false,`):

```dart
    this.acpRuntime,
```

```dart
  /// Tab-scoped ACP runtime when this session is a terminal-less ACP chat.
  /// Null for PTY sessions.
  final AcpChatRuntimeCubit? acpRuntime;
```

- [ ] **Step 4: Branch the chrome resolution**

Inside the `Builder` at ~line 259, the block currently ends with a single `final liveChrome = SessionHistoryLiveChromeX.resolve(...)` followed by the `MarkdownDisplayModeScope` return. Replace that region so the chrome is computed per path and the review widget is built by a closure:

```dart
                                    final turnInFlight = historyTurnInFlight(
                                      isSubmitting: isSubmitting,
                                      awaitingAssistant: state.awaitingAssistant,
                                      sessionBusy: activity.isBusy,
                                      userStoppedTurn: userStoppedTurn,
                                    );
                                    final acpRuntime = widget.acpRuntime;

                                    Widget buildReview(
                                      SessionHistoryLiveChrome liveChrome,
                                    ) => MarkdownDisplayModeScope(
                                      userMessageMode: prefs.userMessageMode,
                                      codeBlockMode: prefs.chatCodeBlockMode,
                                      child: SessionHistoryReviewMessages(
                                        state: state,
                                        runtime: historySeat.runtime,
                                        onRetry: onRetry,
                                        onLoadOlder: historySeat.loadOlder,
                                        liveChrome: liveChrome,
                                        pendingDeliveryStatuses:
                                            historySeat.pendingDeliveryStatuses,
                                        onRetryFailedMessage:
                                            onRetryFailedMessage,
                                        highlightMessageId: highlightMessageId,
                                        revealRequest: revealController,
                                        visibleOwnerId: visibleOwnerId,
                                        scrollAnchorKey: session.sessionId,
                                        scrollAnchors: context
                                            .read<ChatCubit>()
                                            .sessionScrollAnchors,
                                      ),
                                    );

                                    if (acpRuntime != null) {
                                      return BlocBuilder<
                                        AcpChatRuntimeCubit,
                                        AcpChatRuntimeState
                                      >(
                                        bloc: acpRuntime,
                                        builder: (context, acp) => buildReview(
                                          SessionHistoryLiveChromeX.resolveAcp(
                                            turnInFlight: turnInFlight,
                                            phase: acp.phase,
                                            activity: acp.activity,
                                          ),
                                        ),
                                      );
                                    }
                                    return buildReview(
                                      SessionHistoryLiveChromeX.resolve(
                                        turnInFlight: turnInFlight,
                                        memberRunning: memberRunning,
                                        sessionConnecting: sessionConnecting,
                                        isDelivering: activity.isDelivering,
                                        isInTurn: activity.isInTurn,
                                        isAttention: activity.isAttention,
                                      ),
                                    );
```

Copy the remaining `SessionHistoryReviewMessages` arguments verbatim from the existing call site — do not retype them; the closure must match the current construction exactly apart from `liveChrome`.

- [ ] **Step 5: Pass the runtime from the view**

In `client/lib/pages/chat/session_chat_view.dart` at the `SessionChatMessageArea(` construction (~line 1690), add next to `isSubmitting: _isSubmitting,`:

```dart
                                          acpRuntime: widget.acpRuntime,
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart test/pages/chat/session_chat_view_acp_test.dart`
Expected: analyze clean; PASS (including the pre-existing ACP permission-card and Stop tests).

- [ ] **Step 7: Commit**

```bash
git add client/lib/pages/chat/session_chat_message_area.dart client/lib/pages/chat/session_chat_view.dart client/test/pages/chat/session_chat_view_acp_test.dart
git commit -m "fix(acp): resolve the chat footer from the ACP runtime, not PTY signals

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Stop the empty-history flash on first send

**Files:**
- Modify: `client/lib/pages/chat/session_chat_view.dart:1175-1188`
- Modify: `client/lib/pages/chat/session_history_review_messages.dart:65-73`
- Test: `client/test/pages/chat/session_history_review_messages_test.dart`

**Interfaces:**
- Consumes: `SessionHistoryLiveChrome.isActive` (Task 3 gives it three more true-returning values).
- Produces: no new API.

- [ ] **Step 1: Write the failing test**

In `client/test/pages/chat/session_history_review_messages_test.dart`, add `liveChrome` to the `_harness` helper (default `SessionHistoryLiveChrome.none`) and forward it to `SessionHistoryReviewMessages`:

```dart
Widget _harness({
  required AiHistoryState state,
  required AiThreadRuntime runtime,
  Map<String, FailedMessageStatus> pendingDeliveryStatuses = const {},
  ValueChanged<String>? onRetryFailedMessage,
  SessionHistoryLiveChrome liveChrome = SessionHistoryLiveChrome.none,
}) {
```

and inside, add `liveChrome: liveChrome,` to the `SessionHistoryReviewMessages(...)` construction. Add the import:

```dart
import 'package:teampilot/pages/chat/session_history_live_chrome.dart';
```

Then append this test inside `main()`:

```dart
  testWidgets('an active chrome shows the thread, not the empty placeholder', (
    tester,
  ) async {
    final runtime = ExternalStoreAiThreadRuntime();
    await tester.pumpWidget(
      _harness(
        state: const AiHistoryState(status: AiHistoryViewStatus.empty),
        runtime: runtime,
        liveChrome: SessionHistoryLiveChrome.thinking,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No prior messages for this member yet.'), findsNothing);
    expect(find.byType(SessionHistoryThread), findsOneWidget);
    expect(find.text('Thinking…'), findsOneWidget);
  });

  testWidgets('empty history with no chrome still shows the placeholder', (
    tester,
  ) async {
    final runtime = ExternalStoreAiThreadRuntime();
    await tester.pumpWidget(
      _harness(
        state: const AiHistoryState(status: AiHistoryViewStatus.empty),
        runtime: runtime,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No prior messages for this member yet.'), findsOneWidget);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/chat/session_history_review_messages_test.dart`
Expected: the first new test FAILS — the empty placeholder is found while the chrome is active.

- [ ] **Step 3: Guard `_showThread`**

In `client/lib/pages/chat/session_history_review_messages.dart`, replace `_showThread`:

```dart
  bool get _showThread {
    if (state.status == AiHistoryViewStatus.ready) return true;
    if (state.status == AiHistoryViewStatus.refreshing) return true;
    // A turn in flight IS content: the tip chrome is what to show, not an
    // empty-history placeholder. ACP publishes the first message a microtask
    // after submit, so without this the empty pane paints once.
    if (liveChrome.isActive) return true;
    // Optimistic pendings may land while status is still empty/loading, and a
    // refresh failure keeps content under an error status — any content keeps
    // the thread mounted (never the full-pane spinner or a blanked error pane).
    if (runtime.messages.isNotEmpty) return true;
    return false;
  }
```

- [ ] **Step 4: Publish the ACP message before awaiting the draft discard**

In `client/lib/pages/chat/session_chat_view.dart`, replace the ACP branch of `_deliverComposeMessage`:

```dart
    if (_usesAcpTranscript) {
      final acpRuntime = widget.acpRuntime;
      if (acpRuntime == null) {
        return const HistoryContinueSubmitResult.failed();
      }
      // Send before the draft discard: sendPrompt emits synchronously and the
      // seat publish lands in a microtask, so awaiting first leaves one frame
      // painted with the empty "no prior messages" pane.
      final sent = acpRuntime.sendPrompt(text);
      if (clearCompose) {
        await _discardComposeDraftForSubmit();
      }
      return HistoryContinueSubmitResult(
        ok: sent,
        channel: HistoryContinueChannel.pty,
      );
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart test/pages/chat/session_history_review_messages_test.dart test/pages/chat/session_history_review_refreshing_test.dart test/pages/chat/session_history_review_submit_test.dart`
Expected: analyze clean; all three files PASS.

- [ ] **Step 6: Run the full suite before claiming done**

Run: `cd client && dart run tool/run_tests.dart` (background it; read the summary line, not the exit code — the runner exits 0 even on failure).
Expected: no new failures. `client/test/pages/floating_workspace/floating_workspace_panel_gestures_test.dart` has a pre-existing deterministic failure unrelated to this work.

- [ ] **Step 7: Commit**

```bash
git add client/lib/pages/chat/session_chat_view.dart client/lib/pages/chat/session_history_review_messages.dart client/test/pages/chat/session_history_review_messages_test.dart
git commit -m "fix(acp): stop the empty-history pane flashing on first send

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage**

| Spec section | Task |
|---|---|
| §1 `AcpChatActivity` model + transitions | Task 1 |
| §2 attention `working` edge | Task 2 |
| §3 chrome values + `resolveAcp` + labels + arb | Task 3 |
| §3 message area picks the resolver | Task 4 |
| §4 empty flash (both layers) | Task 5 |
| Testing list | each task's test steps + Task 5 Step 6 |

**Type consistency** — `AcpChatActivity` (Task 1) is used verbatim in Tasks 3 and 4. `SessionHistoryLiveChromeX.resolveAcp({turnInFlight, phase, activity})` is defined in Task 3 and called with exactly those names in Task 4. `SessionChatMessageArea.acpRuntime` is introduced in Task 4 Step 3 and passed in Step 5. `_turnActivity()` / `_resetTurnTrackers()` / `_runningToolCalls` / `_seenChunkThisTurn` are introduced once in Task 1 Step 4 and reused in Steps 5-8.

**Out of scope** (per spec, deliberately absent from every task): presence dots for ACP seats, error-recovery entry points, launch sub-phases, any `ended` chrome value.
