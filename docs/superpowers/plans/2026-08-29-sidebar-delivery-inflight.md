# Sidebar Delivery In-Flight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the sidebar session spinner on from operator send until inject latches the turn or the send fails / Stop, so the composer-wait gap no longer looks like a failed send.

**Architecture:** A session-level refcounted `OperatorDeliveryInFlight` flag is OR'd into `TabWorkingAggregator` (and reclaim `inTurn`) the same way `attentionBusy` is. `ChatCubit.withOperatorDeliveryInFlight` wraps connect/wait/inject on Chat continue, landing, follow-up, and automation. Compose Stop zeros the count. Successful inject latches the turn before the wrap's `finally`, so ending in-flight does not drop the spinner.

**Tech Stack:** Dart, Flutter, flutter_bloc, `TabWorkingAggregator`, `ChatCubit`, `AutomationDispatcher`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-29-sidebar-delivery-inflight-design.md` (approved).
- Do not change `SessionPhase` so connecting lasts until inject.
- Do not latch `userTurnActive` at send time; do not change `onConfirmedRunning`.
- Do not abort `ensureMemberInputReady` on Stop (existing race stays); only clear sidebar in-flight.
- Do not change History live chrome, `awaitingAssistant`, or `historyAwaitingIdleGrace`.
- Follow `docs/CODE_QUALITY.md`: no `print`; `AppLogger` for diagnostics; tests mock via constructor injection.
- Every task: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` for touched files, tests green, then a commit.
- Tests live under `client/test/` mirroring `lib/`. Run one file with `cd client && flutter test test/<path>`.

## File structure

| File | Responsibility |
|------|----------------|
| `client/lib/cubits/chat/operator_delivery_in_flight.dart` | Refcounted per-session in-flight tracker. |
| `client/lib/cubits/chat/tab_working_aggregator.dart` | OR `deliveryInFlight` into `workingSessionIds`. |
| `client/lib/cubits/chat/tab_member_reclaim_watch.dart` | Treat delivery in-flight as `inTurn` so composer wait is not reclaimed. |
| `client/lib/cubits/chat/tab_session_runtime_coordinator.dart` | Pass the new callback into aggregator + reclaim. |
| `client/lib/cubits/chat_cubit.dart` | Own the tracker; wrap `submitSessionOperatorMessage`; Stop API. |
| `client/lib/pages/chat_workbench.dart` | Wrap the direct `submitSessionHistoryReviewMessage` call. |
| `client/lib/pages/chat/session_chat_view.dart` | Compose Stop zeros in-flight. |
| `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart` | Wrap landing ensure + inject. |
| `client/lib/services/automation/automation_dispatcher.dart` | Optional wrap around ensure + inject (no `ChatCubit` import). |
| `client/lib/app/app_shell.dart` | Pass cubit tear-off into the dispatcher. |

---

### Task 1: `OperatorDeliveryInFlight` tracker

**Files:**
- Create: `client/lib/cubits/chat/operator_delivery_in_flight.dart`
- Create: `client/test/cubits/chat/operator_delivery_in_flight_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class OperatorDeliveryInFlight { OperatorDeliveryInFlight({void Function()? onChanged}); bool isInFlight(String sessionId); Future<T> run<T>(String sessionId, Future<T> Function() action); void clear(String sessionId); }`
  - Empty/whitespace `sessionId`: `isInFlight` is false; `run` just awaits `action`; `clear` is a no-op.
  - `run` is refcounted: nested `run` on the same id stays in-flight until the outer `finally`.
  - `end` at count 0 is a no-op (`clear` may zero while a `run` is still finishing).
  - `onChanged` fires after begin, after a decrement that changes emptiness, and after `clear` that actually had a count.

- [ ] **Step 1: Write the failing test**

Create `client/test/cubits/chat/operator_delivery_in_flight_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/operator_delivery_in_flight.dart';

void main() {
  test('run lights isInFlight until action completes', () async {
    final tracker = OperatorDeliveryInFlight();
    final gate = Completer<void>();
    final done = tracker.run('sess', () => gate.future);
    expect(tracker.isInFlight('sess'), isTrue);
    expect(tracker.isInFlight('other'), isFalse);
    gate.complete();
    await done;
    expect(tracker.isInFlight('sess'), isFalse);
  });

  test('nested run stays in flight until the outer finally', () async {
    final tracker = OperatorDeliveryInFlight();
    final inner = Completer<void>();
    final outerReleased = Completer<void>();
    final done = tracker.run('sess', () async {
      await tracker.run('sess', () => inner.future);
      await outerReleased.future;
    });
    inner.complete();
    await Future<void>.delayed(Duration.zero);
    expect(tracker.isInFlight('sess'), isTrue);
    outerReleased.complete();
    await done;
    expect(tracker.isInFlight('sess'), isFalse);
  });

  test('exception in action still ends in-flight', () async {
    final tracker = OperatorDeliveryInFlight();
    await expectLater(
      tracker.run('sess', () async {
        throw StateError('boom');
      }),
      throwsA(isA<StateError>()),
    );
    expect(tracker.isInFlight('sess'), isFalse);
  });

  test('clear zeros count while run is outstanding; later end is a no-op', () async {
    final tracker = OperatorDeliveryInFlight();
    final gate = Completer<void>();
    final done = tracker.run('sess', () => gate.future);
    tracker.clear('sess');
    expect(tracker.isInFlight('sess'), isFalse);
    gate.complete();
    await done;
    expect(tracker.isInFlight('sess'), isFalse);
  });

  test('empty session id is a no-op', () async {
    final tracker = OperatorDeliveryInFlight();
    await tracker.run('  ', () async {});
    expect(tracker.isInFlight('  '), isFalse);
    expect(tracker.isInFlight(''), isFalse);
    tracker.clear('');
  });

  test('onChanged fires on begin and end', () async {
    var n = 0;
    final tracker = OperatorDeliveryInFlight(onChanged: () => n++);
    await tracker.run('sess', () async {});
    expect(n, 2);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/chat/operator_delivery_in_flight_test.dart`

Expected: FAIL compiling (`operator_delivery_in_flight.dart` not found).

- [ ] **Step 3: Write minimal implementation**

Create `client/lib/cubits/chat/operator_delivery_in_flight.dart`:

```dart
/// Refcounted per-session flag: an operator send is still in connect/wait/inject.
final class OperatorDeliveryInFlight {
  OperatorDeliveryInFlight({this.onChanged});

  final void Function()? onChanged;
  final Map<String, int> _counts = {};

  bool isInFlight(String sessionId) {
    final id = sessionId.trim();
    if (id.isEmpty) return false;
    return (_counts[id] ?? 0) > 0;
  }

  Future<T> run<T>(String sessionId, Future<T> Function() action) async {
    final id = sessionId.trim();
    if (id.isEmpty) return action();
    _begin(id);
    try {
      return await action();
    } finally {
      _end(id);
    }
  }

  /// Zero the count (compose Stop). Later [run] `finally` must not go negative.
  void clear(String sessionId) {
    final id = sessionId.trim();
    if (id.isEmpty) return;
    if (!_counts.containsKey(id)) return;
    _counts.remove(id);
    onChanged?.call();
  }

  void _begin(String id) {
    _counts[id] = (_counts[id] ?? 0) + 1;
    onChanged?.call();
  }

  void _end(String id) {
    final next = (_counts[id] ?? 0) - 1;
    if (next <= 0) {
      if (!_counts.containsKey(id)) return;
      _counts.remove(id);
      onChanged?.call();
      return;
    }
    _counts[id] = next;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/cubits/chat/operator_delivery_in_flight_test.dart`

Expected: PASS (all 6 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/chat/operator_delivery_in_flight.dart \
  client/test/cubits/chat/operator_delivery_in_flight_test.dart
git commit -m "$(cat <<'EOF'
Add refcounted operator delivery in-flight tracker.

Sidebar send-gap working needs a session flag that survives connect
confirm until inject, including nested wraps and Stop-clear.
EOF
)"
```

---

### Task 2: OR delivery in-flight into working + reclaim

**Files:**
- Modify: `client/lib/cubits/chat/tab_working_aggregator.dart`
- Modify: `client/lib/cubits/chat/tab_member_reclaim_watch.dart`
- Modify: `client/lib/cubits/chat/tab_session_runtime_coordinator.dart`
- Create: `client/test/cubits/chat/tab_working_aggregator_test.dart`
- Modify: `client/test/cubits/chat/tab_member_reclaim_watch_test.dart`

**Interfaces:**
- Consumes: `OperatorDeliveryInFlight.isInFlight` (as `bool Function(String sessionId)? sessionBusyFromDeliveryInFlight`).
- Produces:
  - `TabWorkingAggregator({..., bool Function(String sessionId)? sessionBusyFromDeliveryInFlight})`
  - `compute()` adds `sessionId` when `sessionWorking || attentionBusy || deliveryInFlight`.
  - `TabMemberReclaimWatch({..., bool Function(String sessionId)? sessionBusyFromDeliveryInFlight})` — `inTurn` also ORs this callback.
  - `TabSessionRuntimeCoordinator` factory takes the same optional callback and passes it to aggregator and reclaim.

- [ ] **Step 1: Write the failing aggregator test**

Create `client/test/cubits/chat/tab_working_aggregator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/tab_working_aggregator.dart';
import 'package:teampilot/services/team/session_working_resolver.dart';

void main() {
  TabWorkingAggregator aggregator({
    required ChatTabStore store,
    bool Function(String sessionId)? deliveryInFlight,
    bool Function(String sessionId)? attention,
  }) {
    return TabWorkingAggregator(
      tabStore: store,
      sessionWorking: SessionWorkingResolver(),
      globalPresets: () => const [],
      activeTeam: () => null,
      activeSessionId: () => null,
      presence: () => const {},
      sessionBusyFromAttention: attention,
      sessionBusyFromDeliveryInFlight: deliveryInFlight,
    );
  }

  test('delivery in-flight alone puts the open session in compute()', () {
    final store = ChatTabStore();
    store.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'sess', title: 't', subtitle: 's'),
        cliTeamName: 'ct',
      ),
    );
    final inFlight = <String>{'sess'};
    final working = aggregator(
      store: store,
      deliveryInFlight: inFlight.contains,
    ).compute();
    expect(working, {'sess'});
  });

  test('clearing delivery in-flight with no other busy removes the session', () {
    final store = ChatTabStore();
    store.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'sess', title: 't', subtitle: 's'),
        cliTeamName: 'ct',
      ),
    );
    expect(
      aggregator(store: store, deliveryInFlight: (_) => false).compute(),
      isEmpty,
    );
  });

  test('attention busy still ORs with delivery in-flight', () {
    final store = ChatTabStore();
    store.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'sess', title: 't', subtitle: 's'),
        cliTeamName: 'ct',
      ),
    );
    final working = aggregator(
      store: store,
      attention: (id) => id == 'sess',
      deliveryInFlight: (_) => false,
    ).compute();
    expect(working, {'sess'});
  });
}
```

- [ ] **Step 2: Run aggregator test to verify it fails**

Run: `cd client && flutter test test/cubits/chat/tab_working_aggregator_test.dart`

Expected: FAIL (`sessionBusyFromDeliveryInFlight` is not a defined named parameter).

- [ ] **Step 3: Implement aggregator OR**

In `client/lib/cubits/chat/tab_working_aggregator.dart`, add the callback next to `_sessionBusyFromAttention` and OR it in `compute()`:

Constructor: add `bool Function(String sessionId)? sessionBusyFromDeliveryInFlight` and store as `_sessionBusyFromDeliveryInFlight`.

Replace the last lines of `compute()`:

```dart
      final attentionBusy =
          _sessionBusyFromAttention?.call(sessionId) ?? false;
      final deliveryInFlight =
          _sessionBusyFromDeliveryInFlight?.call(sessionId) ?? false;
      if (sessionWorking || attentionBusy || deliveryInFlight) {
        working.add(sessionId);
      }
```

- [ ] **Step 4: Run aggregator test to verify it passes**

Run: `cd client && flutter test test/cubits/chat/tab_working_aggregator_test.dart`

Expected: PASS.

- [ ] **Step 5: Write the failing reclaim test**

In `client/test/cubits/chat/tab_member_reclaim_watch_test.dart`, add a parameter to `_watch`:

```dart
TabMemberReclaimWatch _watch(
  ChatTabStore store, {
  required void Function(String, String) onDiscard,
  required DateTime Function() now,
  bool Function(String sessionId)? isSessionPinned,
  bool Function(String sessionId)? sessionBusyFromDeliveryInFlight,
}) => TabMemberReclaimWatch(
  tabStore: store,
  reclaimEnabled: () => true,
  activeTeam: () => _team,
  policy: () => const TerminalReclaimPolicy(idleAfter: Duration(seconds: 2)),
  onDiscardMember: onDiscard,
  isSessionPinned: isSessionPinned,
  sessionBusyFromDeliveryInFlight: sessionBusyFromDeliveryInFlight,
  now: now,
);
```

Add this test at the end of `main()` (before the closing `}`), after the existing tests:

```dart
  test('delivery in-flight protects an idle worker from reclaim', () {
    final store = ChatTabStore();
    final tab = _tabWithBus();
    store.registerSession(tab);
    final bus = _busWith(
      'team-lead',
      MemberLifecycle.running,
      MemberActivity.turnDoneReady,
    );
    bus.declareMember(
      AgentNode.test(
        memberId: 'worker-1',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.turnDoneBusWait,
      ),
    );
    tab.teamBus = bus;
    tab.memberShells['team-lead'] = _runningShell();
    tab.memberShells['worker-1'] = _runningShell();

    final discarded = <(String, String)>[];
    var now = DateTime(2026, 8, 9, 12, 0, 0);
    final watch = _watch(
      store,
      onDiscard: (s, m) => discarded.add((s, m)),
      now: () => now,
      sessionBusyFromDeliveryInFlight: (id) => id == 'sess',
    );

    watch.tick();
    now = now.add(const Duration(seconds: 3));
    watch.tick();

    expect(discarded, isEmpty);
  });
```

- [ ] **Step 6: Run reclaim test to verify the new case fails**

Run: `cd client && flutter test test/cubits/chat/tab_member_reclaim_watch_test.dart`

Expected: FAIL (`sessionBusyFromDeliveryInFlight` is not a defined named parameter on `TabMemberReclaimWatch`).

- [ ] **Step 7: Implement reclaim OR + coordinator wiring**

In `client/lib/cubits/chat/tab_member_reclaim_watch.dart`:

- Add field `final bool Function(String sessionId)? _sessionBusyFromDeliveryInFlight;`
- Constructor: `bool Function(String sessionId)? sessionBusyFromDeliveryInFlight` → store it.
- In `_snapshotFor`, change `inTurn`:

```dart
      inTurn: (bus?.isMemberInTurn(memberId) ?? shell.userTurnActive) ||
          (_sessionBusyFromAttention?.call(tab.info.id) ?? false) ||
          (_sessionBusyFromDeliveryInFlight?.call(tab.info.id) ?? false),
```

In `client/lib/cubits/chat/tab_session_runtime_coordinator.dart` factory:

- Add `bool Function(String sessionId)? sessionBusyFromDeliveryInFlight` next to `sessionBusyFromAttention`.
- Pass it into `TabWorkingAggregator(...)` and `TabMemberReclaimWatch(...)`.

- [ ] **Step 8: Run both tests**

Run:

```bash
cd client && flutter test \
  test/cubits/chat/tab_working_aggregator_test.dart \
  test/cubits/chat/tab_member_reclaim_watch_test.dart
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add client/lib/cubits/chat/tab_working_aggregator.dart \
  client/lib/cubits/chat/tab_member_reclaim_watch.dart \
  client/lib/cubits/chat/tab_session_runtime_coordinator.dart \
  client/test/cubits/chat/tab_working_aggregator_test.dart \
  client/test/cubits/chat/tab_member_reclaim_watch_test.dart
git commit -m "$(cat <<'EOF'
Count operator delivery in-flight as sidebar working.

Composer wait after PTY confirm is not a turn latch; OR the new flag
into workingSessionIds and reclaim inTurn so the spinner stays on.
EOF
)"
```

---

### Task 3: ChatCubit wrap + Chat continue + compose Stop

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart`
- Modify: `client/lib/pages/chat_workbench.dart`
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Modify: `client/test/cubits/chat_cubit_simple_working_test.dart`

**Interfaces:**
- Consumes: `OperatorDeliveryInFlight`, `TabSessionRuntimeCoordinator.sessionBusyFromDeliveryInFlight`.
- Produces:
  - `ChatCubit.withOperatorDeliveryInFlight<T>(String sessionId, Future<T> Function() action)`
  - `ChatCubit.endOperatorDeliveryInFlight(String sessionId)` (zeros count)
  - `ChatCubit.isOperatorDeliveryInFlight(String sessionId)` (for tests)
  - `submitSessionOperatorMessage` wraps the `submitSessionHistoryReviewMessage` call with `withOperatorDeliveryInFlight`
  - workbench History `onSubmit` wraps its direct submit the same way
  - `_onUserStoppedTurn` calls `endOperatorDeliveryInFlight(widget.session.sessionId)`

- [ ] **Step 1: Write the failing ChatCubit tests**

Append to `client/test/cubits/chat_cubit_simple_working_test.dart` inside the existing `group('ChatCubit simple-mode working indicator', ...)` (same `setUp` that opens via `requestOpenSession`):

```dart
    test('withOperatorDeliveryInFlight lights workingSessionIds until done', () async {
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/tmp'),
      ]);
      final session = (await repo.createSession(workspace.workspaceId)).session;
      await cubit.loadWorkspaceData(repo);
      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: session,
          workspace: workspace,
          repo: repo,
          connectImmediately: false,
        ),
      );
      await drainPendingAsyncWork();

      final gate = Completer<void>();
      final done = cubit.withOperatorDeliveryInFlight(
        session.sessionId,
        () => gate.future,
      );
      await drainPendingAsyncWork();
      expect(
        cubit.state.workingSessionIds,
        contains(session.sessionId),
        reason: 'sidebar must stay busy during connect/composer wait',
      );
      expect(cubit.isOperatorDeliveryInFlight(session.sessionId), isTrue);

      gate.complete();
      await done;
      await drainPendingAsyncWork();
      expect(cubit.state.workingSessionIds, isEmpty);
    });

    test('endOperatorDeliveryInFlight clears spinner while wrap is outstanding', () async {
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/tmp'),
      ]);
      final session = (await repo.createSession(workspace.workspaceId)).session;
      await cubit.loadWorkspaceData(repo);
      await cubit.requestOpenSession(
        SessionOpenRequest(
          session: session,
          workspace: workspace,
          repo: repo,
          connectImmediately: false,
        ),
      );
      await drainPendingAsyncWork();

      final gate = Completer<void>();
      final done = cubit.withOperatorDeliveryInFlight(
        session.sessionId,
        () => gate.future,
      );
      await drainPendingAsyncWork();
      cubit.endOperatorDeliveryInFlight(session.sessionId);
      await drainPendingAsyncWork();
      expect(cubit.state.workingSessionIds, isEmpty);

      gate.complete();
      await done;
      expect(cubit.state.workingSessionIds, isEmpty);
    });
```

Add `import 'dart:async';` at the top of that file if it is not already present. `SessionOpenRequest` is already imported via `chat_cubit.dart` exports.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/cubits/chat_cubit_simple_working_test.dart`

Expected: FAIL (`withOperatorDeliveryInFlight` is not defined on `ChatCubit`).

- [ ] **Step 3: Wire ChatCubit**

In `client/lib/cubits/chat_cubit.dart`:

1. Import `chat/operator_delivery_in_flight.dart`.

2. Declare **before** `late final TabSessionRuntimeCoordinator _sessionRuntime`:

```dart
  late final OperatorDeliveryInFlight _operatorDeliveryInFlight =
      OperatorDeliveryInFlight(
        onChanged: () {
          if (!isClosed) _recomputeWorkingSessions();
        },
      );
```

3. On the `_sessionRuntime = TabSessionRuntimeCoordinator(...)` call, add:

```dart
        sessionBusyFromDeliveryInFlight: (sessionId) =>
            _operatorDeliveryInFlight.isInFlight(sessionId),
```

4. Public API (place near `_recomputeWorkingSessions`):

```dart
  Future<T> withOperatorDeliveryInFlight<T>(
    String sessionId,
    Future<T> Function() action,
  ) => _operatorDeliveryInFlight.run(sessionId, action);

  void endOperatorDeliveryInFlight(String sessionId) =>
      _operatorDeliveryInFlight.clear(sessionId);

  @visibleForTesting
  bool isOperatorDeliveryInFlight(String sessionId) =>
      _operatorDeliveryInFlight.isInFlight(sessionId);
```

5. In `submitSessionOperatorMessage`, wrap the existing `return submitSessionHistoryReviewMessage(...)` (after `session == null` early return):

```dart
    return withOperatorDeliveryInFlight(
      sessionId,
      () => submitSessionHistoryReviewMessage(
        sessionId: sessionId,
        memberId: shellMemberId,
        message: message,
        connectRequest: ExistingSessionConnect(
          session: session,
          team: team,
          member: connectMember,
          preserveWorkbenchView: preserveWorkbenchView,
        ),
        resolveChannel: resolveChannel,
        connectWorkspaceSession: connectWorkspaceSession,
        ensureMemberInputReady: (sid, mid, {bool directToPty = false}) =>
            _memberMaterializer.ensureMemberInputReady(
              sid,
              mid,
              directToPty: directToPty,
            ),
        deliverUserCommandToMember:
            (sid, mid, text, {bool directToPty = false}) =>
                _sessionRuntime.deliverUserCommandToMember(
                  sid,
                  mid,
                  text,
                  directToPty: directToPty,
                ),
        applyFirstPromptTitle: applyFirstPromptTitle,
      ),
    );
```

Keep the existing argument list; only wrap the call. Do not duplicate connect-request construction — the current method already builds `connectRequest` as `ExistingSessionConnect(...)`. Wrap that existing call as-is:

```dart
    return withOperatorDeliveryInFlight(
      sessionId,
      () => submitSessionHistoryReviewMessage(
        // existing named args unchanged
      ),
    );
```

- [ ] **Step 4: Wrap workbench submit**

In `client/lib/pages/chat_workbench.dart`, replace `return submitSessionHistoryReviewMessage(` with:

```dart
        return chatCubit.withOperatorDeliveryInFlight(
          appSession.sessionId,
          () => submitSessionHistoryReviewMessage(
```

and close with an extra `)`; after the existing submit call's closing `);`.

- [ ] **Step 5: Compose Stop zeros in-flight**

In `client/lib/pages/chat/session_chat_view.dart`, `_onUserStoppedTurn`:

```dart
  void _onUserStoppedTurn() {
    if (_userStoppedTurn.value) return;
    _userStoppedTurn.value = true;
    _seat?.flushHeldTip(endAwaiting: true);
    context.read<ChatCubit>().endOperatorDeliveryInFlight(
      widget.session.sessionId,
    );
  }
```

`ChatCubit` is already imported in this file.

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd client && flutter test test/cubits/chat_cubit_simple_working_test.dart`

Expected: PASS (including the two new tests). Existing idle-watch tests still pass.

- [ ] **Step 7: Commit**

```bash
git add client/lib/cubits/chat_cubit.dart \
  client/lib/pages/chat_workbench.dart \
  client/lib/pages/chat/session_chat_view.dart \
  client/test/cubits/chat_cubit_simple_working_test.dart
git commit -m "$(cat <<'EOF'
Keep sidebar busy for Chat continue until inject.

Wrap History submit with delivery in-flight and clear it on compose
Stop so the composer-wait gap no longer looks like a failed send.
EOF
)"
```

---

### Task 4: Landing + automation wraps

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`
- Modify: `client/lib/services/automation/automation_dispatcher.dart`
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/test/support/post_frame_test_harness.dart` (only if the `AutomationDispatcher(...)` helper there needs the new optional param — it should not; the param is optional)
- Modify: `client/test/services/automation/automation_dispatcher_test.dart`

**Interfaces:**
- Consumes: `ChatCubit.withOperatorDeliveryInFlight`.
- Produces:
  - Landing: `_ensureLandingSessionConnected` + `deliverUserCommandToMember` run inside `chatCubit.withOperatorDeliveryInFlight(session.sessionId, ...)`.
  - `AutomationDispatcher({ Future<T> Function<T>(String sessionId, Future<T> Function() action)? runDeliveryInFlight })` — when null, behavior is unchanged.
  - `_dispatchMessage` runs ensure + deliver inside that wrap when the session id is known.
  - `app_shell.dart` passes `runDeliveryInFlight: chatCubit.withOperatorDeliveryInFlight`.

- [ ] **Step 1: Write the failing automation wrap test**

In `client/test/services/automation/automation_dispatcher_test.dart`, add:

```dart
  test('scheduledMessage wraps ensure+deliver in runDeliveryInFlight', () async {
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final repo = AutomationRepository(fs: AppStorage.fs, layout: layout);
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: 'ws1',
      sessionTeam: 'team-1',
      createdAt: 1,
    );
    final workspace = Workspace(workspaceId: 'ws1', createdAt: 1);
    final team = TeamProfile(
      id: 'team-1',
      name: 'Team',
      members: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
    );
    final bus = _RecordingBusGateway();
    final events = <String>[];

    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: AutomationScheduleCalculator(),
      sessionRepository: _FakeSessionRepository([session]),
      busGateway: bus,
      requestOpenSession: (_) async => SessionOpenStatus.opened,
      requestCreateAndOpenSession: (_) async => SessionOpenStatus.opened,
      workspaceById: (_) => workspace,
      teamById: (id) => id == 'team-1' ? team : null,
      nowMs: () => 100,
      runDeliveryInFlight: <T>(sessionId, action) async {
        events.add('begin:$sessionId');
        try {
          return await action();
        } finally {
          events.add('end:$sessionId');
        }
      },
    );

    await dispatcher.dispatch(
      _scheduledMessageAutomation(sessionId: 'sess-1'),
    );

    expect(events, ['begin:sess-1', 'end:sess-1']);
    expect(bus.ensureCalls, [('sess-1', 'team-lead')]);
    expect(bus.deliverCalls, [('sess-1', 'team-lead', '/clear')]);
    expect(events.indexOf('begin:sess-1'), lessThan(events.indexOf('end:sess-1')));
  });
```

Place it after `'scheduledMessage delivers message when session is connected'`.

- [ ] **Step 2: Run the new automation test to verify it fails**

Run: `cd client && flutter test test/services/automation/automation_dispatcher_test.dart`

Expected: FAIL (`runDeliveryInFlight` is not a defined named parameter).

- [ ] **Step 3: Implement dispatcher wrap**

In `client/lib/services/automation/automation_dispatcher.dart`:

Constructor: add optional named

```dart
    Future<T> Function<T>(
      String sessionId,
      Future<T> Function() action,
    )? runDeliveryInFlight,
```

Store as `_runDeliveryInFlight`.

Add:

```dart
  Future<T> _inFlight<T>(
    String sessionId,
    Future<T> Function() action,
  ) {
    final run = _runDeliveryInFlight;
    if (run == null) return action();
    return run(sessionId, action);
  }
```

In `_dispatchMessage`, after `session` and `memberId` are resolved (the `session == null` branch unchanged), wrap from `_ensureSessionConnected` through deliver + success bookkeeping:

```dart
    return _inFlight(session.sessionId, () async {
      final connected = await _ensureSessionConnected(
        session,
        memberId: memberId,
      );
      if (!connected) {
        final failed = _finishRun(
          pending,
          AutomationRunStatus.dispatchFailed,
          startedAtMs: startedAtMs,
          sessionId: session.sessionId,
          error: 'member_not_ready',
        );
        final updated = _advanceAutomationAfterRun(
          automation,
          lastRunAtMs: startedAtMs,
        );
        return (failed, updated);
      }

      await _busGateway.deliverUserCommandToMember(
        session.sessionId,
        memberId,
        automation.message,
      );
      await _repository.upsertRun(
        automation.workspaceId,
        _finishRun(
          pending,
          AutomationRunStatus.dispatched,
          startedAtMs: startedAtMs,
          sessionId: session.sessionId,
        ),
      );
      final completed = _finishRun(
        pending,
        AutomationRunStatus.completed,
        startedAtMs: startedAtMs,
        sessionId: session.sessionId,
      );
      final updated = _advanceAutomationAfterRun(
        automation,
        lastRunAtMs: startedAtMs,
        dispatchedSessionId: session.sessionId,
      );
      return (completed, updated);
    });
```

Do not import `ChatCubit`. Existing dispatcher tests that omit `runDeliveryInFlight` must still pass.

In `client/lib/app/app_shell.dart`, on `AutomationDispatcher(` add:

```dart
    runDeliveryInFlight: chatCubit.withOperatorDeliveryInFlight,
```

- [ ] **Step 4: Wrap landing ensure + inject**

In `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`, replace the block from `final connected = await _ensureLandingSessionConnected(` through the inject `try/catch` with one wrap. Keep pending-fail + toast behavior:

```dart
  return chatCubit.withOperatorDeliveryInFlight(session.sessionId, () async {
    final connected = await _ensureLandingSessionConnected(
      chatCubit: chatCubit,
      session: session,
      memberId: memberId,
    );
    if (!connected) {
      appLogger.w(
        'submitWorkspaceLandingMessage: member not ready '
        'session=${session.sessionId} member=$memberId',
      );
      if (pendingRecord != null) {
        await chatCubit.markHistoryPendingFailed(
          workspaceId: liveWorkspace.workspaceId,
          sessionId: session.sessionId,
          memberId: historyMemberId,
          record: pendingRecord,
        );
      }
      if (context.mounted) {
        AppToast.show(
          context,
          message: l10n.homeWorkspaceNewConversation,
          variant: TpToastVariant.error,
        );
      }
      return false;
    }

    try {
      await chatCubit.sessionRuntime.deliverUserCommandToMember(
        session.sessionId,
        memberId,
        trimmed,
        directToPty: true,
      );
      return true;
    } on Object catch (error, stackTrace) {
      if (pendingRecord != null) {
        await chatCubit.markHistoryPendingFailed(
          workspaceId: liveWorkspace.workspaceId,
          sessionId: session.sessionId,
          memberId: historyMemberId,
          record: pendingRecord,
        );
      }
      appLogger.e(
        'submitWorkspaceLandingMessage',
        error: error,
        stackTrace: stackTrace,
      );
      if (context.mounted) {
        AppToast.show(
          context,
          message: '${l10n.homeWorkspaceNewConversation}: $error',
          variant: TpToastVariant.error,
        );
      }
      return false;
    }
  });
```

`submitWorkspaceLandingMessage` currently returns `false` after that block on various paths; the wrap's `return false/true` must remain the function's return. Persist-pending stays **outside** the wrap (bubble can appear before spinner; spinner must cover ensure+inject).

- [ ] **Step 5: Run automation tests + ChatCubit working tests**

Run:

```bash
cd client && flutter test \
  test/services/automation/automation_dispatcher_test.dart \
  test/cubits/chat_cubit_simple_working_test.dart \
  test/cubits/chat/operator_delivery_in_flight_test.dart \
  test/cubits/chat/tab_working_aggregator_test.dart \
  test/cubits/chat/tab_member_reclaim_watch_test.dart
```

Expected: PASS.

- [ ] **Step 6: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no issues in touched files.

- [ ] **Step 7: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/workspace_session_actions.dart \
  client/lib/services/automation/automation_dispatcher.dart \
  client/lib/app/app_shell.dart \
  client/test/services/automation/automation_dispatcher_test.dart
git commit -m "$(cat <<'EOF'
Keep sidebar busy for landing and automation inject.

The same delivery in-flight wrap covers composer wait on first-prompt
and scheduled dispatch so those sends do not look dropped mid-connect.
EOF
)"
```

---

## Self-review

**Spec coverage**

| Spec requirement | Task |
|------------------|------|
| Session-level in-flight flag, refcounted, end at 0 is no-op | Task 1 |
| Aggregator OR `deliveryInFlight` | Task 2 |
| Reclaim `inTurn` ORs the same callback | Task 2 |
| Begin/end recompute working without waiting for idle-watch | Task 3 (`onChanged` → `_recomputeWorkingSessions`) |
| Wrap `submitSessionOperatorMessage` | Task 3 |
| Wrap workbench direct submit | Task 3 |
| Compose Stop zeros count | Task 3 |
| Landing ensure + inject wrap | Task 4 |
| Automation wrap without importing ChatCubit | Task 4 |
| Empty no-op | Task 1 |
| Failed send `finally` ends in-flight | Task 1 + wraps |
| Success latch before finally keeps spinner | Task 3 (inject still calls `latchTurnStarted` inside the wrap) |
| Follow-up via `submitSessionOperatorMessage` | Task 3 |
| Do not begin inside `ensureMemberInputReady` alone | Tasks 3–4 wrap orchestrators |

**Placeholders:** none.

**Type consistency:** `sessionBusyFromDeliveryInFlight` is `bool Function(String sessionId)?` on aggregator, reclaim, and coordinator. `withOperatorDeliveryInFlight` / `runDeliveryInFlight` are `Future<T> Function<T>(String sessionId, Future<T> Function() action)`.
