# Session Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `workingSessionIds` with a session-level `SessionActivity` snapshot so spinner, History, reclaim, and idle-notify each follow the correct view.

**Architecture:** `SessionActivityAggregator` emits per-session **reasons** (`delivering` / `inTurn` / `attention`). `reduceSessionActivity` merges that with the previous snapshot to set `hadTurn` and `disposition`. PTY quiet is a turn-end **proposal** gated by `TeamBehaviorCapability.requiresPtyFallback`. Notify fires only on `isReadyToChat`.

**Tech Stack:** Flutter / Dart, `flutter_bloc`, existing `CliToolRegistry` capabilities, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-30-session-activity-design.md`

## Global Constraints

- Spec wins over this plan if they drift.
- No 4s notify debounce. No stretching `SessionPhase` through inject. Do not latch `userTurnActive` at send time.
- l10n: do not add copy unless a user-visible string changes (none expected).
- Tests: `cd client && flutter test <files listed in the task>`. Do not run the full suite unless the task says so.
- Do **not** git commit unless the user explicitly asks (repo rule). Skip every Commit step.
- `ChatState.workingSessionIds` and `turnWorkingSessionIds` are removed. Use `sessionActivities` / `busySessionIds`.
- Commands run from `client/` unless noted.

## File map

| File | Role |
|------|------|
| Create `client/lib/models/session_activity.dart` | Reasons, disposition, snapshot, views |
| Create `client/lib/services/session/session_activity_reduce.dart` | Merge previous snapshot + current reasons |
| Create `client/lib/services/session/pty_quiet_turn_end.dart` | `ptyQuietEndsTurn(CliTool)` |
| Replace `tab_working_aggregator.dart` | `SessionActivityAggregator` → reasons map |
| Modify `chat_state.dart` | `sessionActivities` + `busySessionIds` getter |
| Modify `chat_cubit.dart` | Reduce, emit, acknowledge ready, Stop/fail disposition, done → `endTurn` |
| Modify `tab_session_idle_watch.dart` | Gate `endTurn` on policy |
| Modify `session_idle_notify_gate.dart` | Rising `isReadyToChat` |
| Modify History chrome + UI contains() sites | Follow activity views |
| Tests | Mirror each unit above |

---

### Task 1: `SessionActivity` model

**Files:**
- Create: `client/lib/models/session_activity.dart`
- Test: `client/test/models/session_activity_test.dart`

**Interfaces:**
- Produces: `SessionBusyReason`, `SessionTurnDisposition`, `SessionActivity` with `isBusy`, `isDelivering`, `inTurn`, `isAttention`, `isReadyToChat`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_activity.dart';

void main() {
  test('empty activity is not busy and not ready', () {
    const a = SessionActivity();
    expect(a.isBusy, isFalse);
    expect(a.isReadyToChat, isFalse);
  });

  test('delivering is busy but not ready', () {
    const a = SessionActivity(reasons: {SessionBusyReason.delivering});
    expect(a.isBusy, isTrue);
    expect(a.isReadyToChat, isFalse);
  });

  test('ready only when idle, hadTurn, completed', () {
    const a = SessionActivity(
      hadTurn: true,
      disposition: SessionTurnDisposition.completed,
    );
    expect(a.isReadyToChat, isTrue);
  });

  test('cancelled or failed is not ready', () {
    expect(
      const SessionActivity(
        hadTurn: true,
        disposition: SessionTurnDisposition.cancelled,
      ).isReadyToChat,
      isFalse,
    );
    expect(
      const SessionActivity(
        hadTurn: true,
        disposition: SessionTurnDisposition.failed,
      ).isReadyToChat,
      isFalse,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/session_activity_test.dart`

Expected: compile error — file `session_activity.dart` missing.

- [ ] **Step 3: Write minimal implementation**

`client/lib/models/session_activity.dart`:

```dart
import 'package:equatable/equatable.dart';

enum SessionBusyReason { delivering, inTurn, attention }

enum SessionTurnDisposition { none, completed, cancelled, failed }

class SessionActivity extends Equatable {
  const SessionActivity({
    this.reasons = const {},
    this.hadTurn = false,
    this.disposition = SessionTurnDisposition.none,
  });

  final Set<SessionBusyReason> reasons;
  final bool hadTurn;
  final SessionTurnDisposition disposition;

  bool get isBusy => reasons.isNotEmpty;
  bool get isDelivering => reasons.contains(SessionBusyReason.delivering);
  bool get isInTurn => reasons.contains(SessionBusyReason.inTurn);
  bool get isAttention => reasons.contains(SessionBusyReason.attention);
  bool get isReadyToChat =>
      !isBusy &&
      hadTurn &&
      disposition == SessionTurnDisposition.completed;

  SessionActivity copyWith({
    Set<SessionBusyReason>? reasons,
    bool? hadTurn,
    SessionTurnDisposition? disposition,
  }) => SessionActivity(
    reasons: reasons ?? this.reasons,
    hadTurn: hadTurn ?? this.hadTurn,
    disposition: disposition ?? this.disposition,
  );

  @override
  List<Object?> get props => [reasons, hadTurn, disposition];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/session_activity_test.dart`

Expected: All tests passed.

- [ ] **Step 5: Commit** — skip unless user asked.

---

### Task 2: `reduceSessionActivity`

**Files:**
- Create: `client/lib/services/session/session_activity_reduce.dart`
- Test: `client/test/services/session/session_activity_reduce_test.dart`

**Interfaces:**
- Consumes: `SessionActivity`
- Produces: `SessionActivity reduceSessionActivity({required SessionActivity previous, required Set<SessionBusyReason> reasons, SessionTurnDisposition? forced})`

Rules:
- `hadTurn` becomes true if previous.hadTurn **or** reasons contains `inTurn` or `attention`.
- If `forced != null`, use it as disposition (Stop / fail).
- Else if reasons is empty and previous had `inTurn` or `attention` (or previous.hadTurn with previous.inTurn/attention): `completed`.
- Else if reasons empty and previous was delivering-only (no hadTurn): `failed`.
- Else if reasons non-empty: disposition `none` (still busy).
- After `completed`/`failed`/`cancelled` with empty reasons, keep hadTurn as computed so `isReadyToChat` can be true for completed only.

When still busy, disposition is `none`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_activity.dart';
import 'package:teampilot/services/session/session_activity_reduce.dart';

void main() {
  test('delivering only is busy, not ready', () {
    final next = reduceSessionActivity(
      previous: const SessionActivity(),
      reasons: {SessionBusyReason.delivering},
    );
    expect(next.isBusy, isTrue);
    expect(next.hadTurn, isFalse);
    expect(next.isReadyToChat, isFalse);
  });

  test('dropping delivering without a turn is failed, not ready', () {
    final next = reduceSessionActivity(
      previous: const SessionActivity(reasons: {SessionBusyReason.delivering}),
      reasons: {},
    );
    expect(next.disposition, SessionTurnDisposition.failed);
    expect(next.isReadyToChat, isFalse);
  });

  test('inTurn then empty is completed ready', () {
    final mid = reduceSessionActivity(
      previous: const SessionActivity(reasons: {SessionBusyReason.delivering}),
      reasons: {SessionBusyReason.inTurn},
    );
    expect(mid.hadTurn, isTrue);
    final done = reduceSessionActivity(previous: mid, reasons: {});
    expect(done.isReadyToChat, isTrue);
  });

  test('Stop forced cancelled is not ready', () {
    final next = reduceSessionActivity(
      previous: const SessionActivity(
        reasons: {SessionBusyReason.inTurn},
        hadTurn: true,
      ),
      reasons: {},
      forced: SessionTurnDisposition.cancelled,
    );
    expect(next.isReadyToChat, isFalse);
    expect(next.disposition, SessionTurnDisposition.cancelled);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/session/session_activity_reduce_test.dart`

Expected: missing `reduceSessionActivity`.

- [ ] **Step 3: Implement**

```dart
import '../../models/session_activity.dart';

SessionActivity reduceSessionActivity({
  required SessionActivity previous,
  required Set<SessionBusyReason> reasons,
  SessionTurnDisposition? forced,
}) {
  final hadTurn =
      previous.hadTurn ||
      reasons.contains(SessionBusyReason.inTurn) ||
      reasons.contains(SessionBusyReason.attention);
  if (reasons.isNotEmpty) {
    return SessionActivity(reasons: reasons, hadTurn: hadTurn);
  }
  final disposition =
      forced ??
      (hadTurn &&
              (previous.isInTurn ||
                  previous.isAttention ||
                  previous.hadTurn)
          ? SessionTurnDisposition.completed
          : (previous.isDelivering
                ? SessionTurnDisposition.failed
                : SessionTurnDisposition.none));
  // If we never had a turn, empty reasons after delivering is failed.
  // If we had a turn and reasons cleared without forced → completed.
  return SessionActivity(
    reasons: const {},
    hadTurn: hadTurn,
    disposition: disposition,
  );
}
```

Fix the empty-without-hadTurn branch so delivering-only → `failed`, idle→idle stays `none`:

```dart
SessionTurnDisposition _disposition({
  required SessionActivity previous,
  required bool hadTurn,
  SessionTurnDisposition? forced,
}) {
  if (forced != null) return forced;
  if (hadTurn && (previous.isInTurn || previous.isAttention)) {
    return SessionTurnDisposition.completed;
  }
  if (previous.isDelivering && !previous.hadTurn) {
    return SessionTurnDisposition.failed;
  }
  return SessionTurnDisposition.none;
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/services/session/session_activity_reduce_test.dart`

Expected: All tests passed.

- [ ] **Step 5: Commit** — skip unless user asked.

---

### Task 3: `ptyQuietEndsTurn`

**Files:**
- Create: `client/lib/services/session/pty_quiet_turn_end.dart`
- Test: `client/test/services/session/pty_quiet_turn_end_test.dart`

**Interfaces:**
- Consumes: `CliTool`, `CliToolRegistry`
- Produces: `bool ptyQuietEndsTurn(CliTool cli, {CliToolRegistry? registry})`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/session/pty_quiet_turn_end.dart';

void main() {
  test('Cursor PTY quiet ends the turn; Claude does not', () {
    expect(ptyQuietEndsTurn(CliTool.cursor), isTrue);
    expect(ptyQuietEndsTurn(CliTool.claude), isFalse);
    expect(ptyQuietEndsTurn(CliTool.codex), isFalse);
  });
}
```

- [ ] **Step 2: Run — expect fail** (missing library).

- [ ] **Step 3: Implement**

```dart
import '../cli/registry/capabilities/team_behavior_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../../models/team_config.dart';

bool ptyQuietEndsTurn(CliTool cli, {CliToolRegistry? registry}) {
  final cap = (registry ?? CliToolRegistry.builtIn())
      .capability<TeamBehaviorCapability>(cli);
  return cap?.requiresPtyFallback ?? false;
}
```

- [ ] **Step 4: Run tests — expect pass.**

- [ ] **Step 5: Commit** — skip unless user asked.

---

### Task 4: `SessionActivityAggregator`

**Files:**
- Create: `client/lib/cubits/chat/session_activity_aggregator.dart`
- Test: `client/test/cubits/chat/session_activity_aggregator_test.dart`
- Modify: keep `tab_working_aggregator.dart` until Task 5 switches call sites, then delete it.

**Interfaces:**
- Same constructor deps as `TabWorkingAggregator`.
- Produces: `Map<String, Set<SessionBusyReason>> computeReasons()`

For each open tab:
- `delivering` if `sessionBusyFromDeliveryInFlight`
- `inTurn` if current `tabHasWorkingMember` / presence working (the old `sessionWorking` **without** treating delivery as working — member latch/presence only)
- `attention` if `sessionBusyFromAttention`

Do **not** put delivery into `inTurn`.

- [ ] **Step 1: Write tests** (delivery-only → `{delivering}`; attention-only → `{attention}`; member working → `{inTurn}`; all three).

Port `tab_working_aggregator_test.dart` to reasons. Include: `computeReasons()['sess']` for delivery-only is `{SessionBusyReason.delivering}` and does not include `inTurn`.

- [ ] **Step 2: Run — expect fail.**

- [ ] **Step 3: Implement aggregator** by copying `TabWorkingAggregator` and returning a map of reason sets instead of a set of ids. `inTurn` = old `sessionWorking` path only (presence or `tabHasWorkingMember`). Never OR delivery into `inTurn`.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit** — skip unless user asked.

---

### Task 5: ChatState + ChatCubit emit

**Files:**
- Modify: `client/lib/cubits/chat/model/chat_state.dart`
- Modify: `client/lib/cubits/chat_cubit.dart` (`_updateWorkingSessions` → `_updateSessionActivities`)
- Modify: `client/lib/cubits/chat/tab_session_runtime_coordinator.dart` (`recomputeWorkingSessions` → `computeReasons`)
- Delete: `tab_working_aggregator.dart` once unused
- Tests: update `chat_cubit_simple_working_test.dart` and any `copyWith(workingSessionIds:)` to `sessionActivities` / `busySessionIds`

**Interfaces:**
- `ChatState.sessionActivities` → `Map<String, SessionActivity>`
- `Set<String> get busySessionIds`
- `bool isSessionBusy(String id)`
- Cubit `_forcedDisposition` map (Stop/fail) consumed on next reduce, then cleared
- `void acknowledgeSessionReady(String sessionId)` sets that activity to `SessionActivity()` so `isReadyToChat` does not stick

`_updateSessionActivities`:
```dart
void _updateSessionActivities() {
  final reasons = _sessionRuntime.computeReasons();
  final next = <String, SessionActivity>{};
  for (final tab in _tabStore.openTabs) {
    final id = tab.info.id;
    final prev = state.sessionActivities[id] ?? const SessionActivity();
    final forced = _forcedDisposition.remove(id);
    next[id] = reduceSessionActivity(
      previous: prev,
      reasons: reasons[id] ?? const {},
      forced: forced,
    );
  }
  if (mapEquals(next, state.sessionActivities)) return;
  emit(state.copyWith(sessionActivities: next));
}
```

Replace every `workingSessionIds.contains(id)` with `state.isSessionBusy(id)` or `busySessionIds`.

`endOperatorDeliveryInFlight` / failed submit: if wrap ends with no latch, reduce yields `failed` — no notify.

Compose Stop: ` _forcedDisposition[id] = cancelled`; `endOperatorDeliveryInFlight`; `endTurn` on seats; recompute.

- [ ] **Step 1: Write/adjust failing cubit tests** for `delivering` lights `busySessionIds` and `sessionActivities[id]!.isDelivering`; after wrap with no latch, not busy and not `isReadyToChat`.

- [ ] **Step 2: Run `flutter test test/cubits/chat_cubit_simple_working_test.dart` — expect compile failures.**

- [ ] **Step 3: Implement state + cubit + mechanical call-site updates listed in Task 8 if blocked on compile.** Prefer finishing emit path here and leaving History chrome to Task 8 if the file is huge.

Mechanical replacements in this task if the app must compile:
- `sidebar_session_tile.dart`, `session_seat_working.dart`, `workspace_sidebar.dart`, `worktree_group_section.dart`, `workspace_shell_tabs.dart`, `right_tools_tool_views.dart`, `terminal_follow_up_compose.dart`, `running_session_ids.dart`, `workspace_running_sessions.dart`, tests that construct `ChatState(workingSessionIds: …)`.

- [ ] **Step 4: Cubit tests pass.**

- [ ] **Step 5: Commit** — skip unless user asked.

---

### Task 6: Idle-watch respects `ptyQuietEndsTurn`

**Files:**
- Modify: `client/lib/cubits/chat/tab_session_idle_watch.dart`
- Modify: `client/lib/cubits/chat/tab_member_coordination_factory.dart` if CLI resolve lives there
- Test: `client/test/cubits/chat/tab_session_idle_watch_test.dart`

**Interfaces:**
- Idle watch `endTurn` callback runs only when `ptyQuietEndsTurn(memberCli)` is true.
- Resolve member CLI the same way `ChatCubit._onTurnEnded` does (`SessionMemberCliResolver` + tab session + team). If session/CLI missing, `ptyQuietEndsTurn` is false (do not end).

- [ ] **Step 1: Change existing test** `onAfterTurnEnded fires on PTY-quiet turn end` to use a **Cursor** personal session (`persistedSession` with `cli: CliTool.cursor`) so quiet still ends. Add a second test: Claude/simple default session — quiet does **not** call `onAfterTurnEnded`.

- [ ] **Step 2: Run — Claude case should fail** (still ends today).

- [ ] **Step 3: In `tick`, wrap `endTurn:`**

```dart
endTurn: () {
  final cli = /* resolve */;
  if (!ptyQuietEndsTurn(cli)) return;
  coordination.endTurn();
  _onAfterTurnEnded?.call(tab.info.id, memberId);
},
```

Need `CliTool` on the tab: from `tab.persistedSession` + factory. Inject `CliTool Function(ChatTab tab, String memberId) memberCli` on the watch to keep it testable.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit** — skip unless user asked.

---

### Task 7: Done hook ends `inTurn` when PTY quiet does not

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart` (attention listener or existing apply path)
- Test: extend `client/test/cubits/chat_cubit_turn_end_test.dart` or new `chat_cubit_session_activity_test.dart`

**Interfaces:**
- When `AgentAttentionCubit` seat becomes `done` (and `!sessionIsAgentActive`) for a seat whose CLI has `requiresPtyFallback == false`, call `coordination.endTurn()` then recompute.
- Cursor: do **not** extra-end on done if quiet already ended; if done fires first, still `endTurn` (idempotent).

- [ ] **Step 1: Failing test** — personal Claude session, `markUserTurnStarted`, `debugRecomputeWorkingSessions`, expect busy; apply `AgentSeatAttention.done`; expect not busy and `isReadyToChat` true (before acknowledge).

- [ ] **Step 2: Run — expect still busy** (latch not cleared).

- [ ] **Step 3: Wire** a listener on attention (or from `applyEvent` host callback) → `endTurn` for that member. Reuse seat coordination factory.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit** — skip unless user asked.

---

### Task 8: Idle notify on `isReadyToChat`

**Files:**
- Modify: `client/lib/services/notification/session_idle_notify_gate.dart`
- Modify: `client/lib/widgets/notification/session_idle_notification_listener.dart`
- Modify: `client/test/services/notification/session_idle_notify_gate_test.dart`
- Cubit: after notify, `acknowledgeSessionReady` so the flag does not retrigger

**Interfaces:**
- `SessionIdleNotifyGate.handle(Map<String, SessionActivity> activities)`
- Rising edge: `previous[id]?.isReadyToChat != true` && `next[id]?.isReadyToChat == true`

- [ ] **Step 1: Rewrite gate tests**

```dart
test('delivering drop does not notify', () {
  gate.handle({'s1': delivering});
  gate.handle({'s1': failedIdle});
  expect(confirmed, isEmpty);
});

test('completed idle notifies once', () {
  gate.handle({'s1': inTurn});
  gate.handle({'s1': ready});
  expect(confirmed, [{'s1'}]);
  gate.handle({'s1': ready});
  expect(confirmed, [{'s1'}]); // still one until ack clears
});
```

Listener `listenWhen`: `previous.sessionActivities != next.sessionActivities`. On confirm, `chat.acknowledgeSessionReady(id)` then notify service (same skip focused+active as today).

- [ ] **Step 2: Run — expect fail.**

- [ ] **Step 3: Implement gate + listener.** Delete turnWorking/working dual handle.

- [ ] **Step 4: `flutter test test/services/notification/session_idle_notify_gate_test.dart test/services/notification/session_idle_notification_service_test.dart`**

- [ ] **Step 5: Commit** — skip unless user asked.

---

### Task 9: History live chrome from activity

**Files:**
- Modify: `client/lib/pages/chat/session_history_live_chrome.dart`
- Modify: `client/lib/pages/chat/session_chat_view.dart` / `session_chat_message_area.dart` callers
- Test: `client/test/pages/chat/session_history_live_chrome_test.dart`

**Interfaces:**
- `historyTurnInFlight` takes `sessionBusy` (any reason) instead of `sessionWorking`, still Stop-suppressed.
- `resolve`: delivering (or connecting / !memberRunning) → `starting`; `inTurn` or `attention` → `running`.

- [ ] **Step 1: Tests** — delivering + not member running → starting; inTurn → running; cancelled/Stop → none when `userStoppedTurn`.

- [ ] **Step 2: Fail then implement.**

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit** — skip unless user asked.

---

### Task 9b: Reclaim

Reclaim already ORs delivery + attention + inTurn via callbacks. Point `inTurn` callback at `state.isSessionBusy(sessionId)` **or** keep the three callbacks if they still match reasons. After Task 5, `sessionBusyFromDeliveryInFlight` remains valid. No behavior change if `isBusy` is the OR of the three reasons.

Verify `tab_member_reclaim_watch_test.dart` still passes. If a test assumed PTY-quiet ended inTurn for Claude, update.

---

### Task 10: Remaining tests and integration

**Files:** all remaining `workingSessionIds` references from repo grep.

- [ ] Replace with `busySessionIds` / `isSessionBusy`.
- [ ] Integration tests (`session_idle_busy_integration_test.dart`, `turn_completion_*`): Claude path — PTY quiet must **not** clear busy; done/stop hook should. Cursor path — quiet still clears. Adjust assertions; do not weaken to timeouts.
- [ ] Run:

```
flutter test test/models/session_activity_test.dart \
  test/services/session/session_activity_reduce_test.dart \
  test/services/session/pty_quiet_turn_end_test.dart \
  test/cubits/chat/session_activity_aggregator_test.dart \
  test/cubits/chat/tab_session_idle_watch_test.dart \
  test/cubits/chat_cubit_simple_working_test.dart \
  test/cubits/chat_cubit_turn_end_test.dart \
  test/pages/chat/session_history_live_chrome_test.dart \
  test/services/notification/session_idle_notify_gate_test.dart \
  test/cubits/chat/tab_member_reclaim_watch_test.dart
```

Expected: All tests passed.

If `managed_provider_editor_field_examples.dart` l10n compile errors block unrelated files, do not “fix” that in this work unless the test you must run cannot load.

---

## Spec coverage

| Spec | Task |
|------|------|
| SessionActivity reasons + views | 1 |
| hadTurn / disposition | 2 |
| PTY quiet policy | 3, 6 |
| Aggregator | 4 |
| ChatState / cubit | 5 |
| Done ends Claude inTurn | 7 |
| Notify once on ready | 8 |
| History Starting/Running | 9 |
| Spinner / reclaim = isBusy | 5, 9b |
| Open without send | 5 (empty map) |

---

## Execution

Plan saved to `docs/superpowers/plans/2026-08-30-session-activity.md`.
