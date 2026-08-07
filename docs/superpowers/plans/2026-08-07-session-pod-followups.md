# SessionPod Follow-ups: runtime pod + pod-owned HistoryStore + thin ChatCubit

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the two remaining spec items (`docs/superpowers/specs/2026-08-07-session-pod-architecture-design.md`): the pod owns a per-session, member-partitioned `HistoryStore`, and `ChatCubit` becomes a thin pod registry instead of holding the session detail graph.

**Architecture:** `SessionPod` becomes a mutable runtime object (one per open session) owning its `HistoryStore`, member shells, and keep-alive identity — replacing `ChatTab` as the per-session runtime. The pod publishes an immutable `SessionPodState` value (phase/member/view/revision) for selectors. `HistoryStore` is per-session and partitions by member; `SessionChatView` binds the store's member seat via the pod instead of the global `AiHistoryCubit`. `ChatCubit` shrinks to a pod registry + active id; the launch machinery drives pods, not tabs.

**Tech Stack:** Flutter / flutter_bloc cubits, `ai_message_core` (`AiHistorySeat` extends `Cubit<AiHistoryState>`), existing `ChatTabStore`/`ChatTab`. Tests: `flutter test` (unit + widget), harness `client/test/support/post_frame_test_harness.dart`.

## Global Constraints

- Follow the spec (above); keep the already-landed behavior: cache-first `HistoryStore` status machine (`initialLoading/ready/refreshing/error/empty`), no-blank invariant, per-session `SessionPhase`, pure `resolveWorkbenchOverlay`, keep-alive session stack, landing scoped progress.
- Every task ends green: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test <target>`.
- Commit after each task.
- The pod runtime object is pure-Dart (no `BuildContext`).

---

## Phase 1 — SessionPod becomes a runtime object

### Task 1: `SessionPod` runtime + `SessionPodState` value

**Files:**
- Modify: `client/lib/cubits/session/session_pod.dart`
- Modify: `client/lib/cubits/chat_cubit.dart` (registry now holds runtime pods)
- Modify: `client/lib/cubits/chat/chat_connect_state_mixin.dart`
- Test: `client/test/cubits/session/session_pod_test.dart`, `client/test/cubits/session/session_phase_drive_test.dart`, `client/test/cubits/chat_cubit_pod_registry_test.dart`

**Interfaces:**
- Produces:
  - `class SessionPodState { String sessionId; String workspaceId; SessionPhase phase; String? launchError; String selectedMemberId; SessionWorkbenchView view; int revision; }` — immutable, `==`/`hashCode` on `(sessionId, revision)`.
  - `class SessionPod { SessionPod({required String sessionId, required String workspaceId, AiHistoryLoader? loader}); String sessionId; String workspaceId; SessionPodState get state; void setPhase(SessionPhase p); void setLaunchError(String? e); void selectMember(String id); void setView(SessionWorkbenchView v); }` — the runtime object; mutators bump `revision` and fire a notify callback.
  - `ChatCubit.podRuntime(String sessionId) → SessionPod?`, `ChatCubit.ensurePodRuntime(String sessionId) → SessionPod`, `ChatCubit.updatePodState(SessionPodState)` (bump + emit), `SessionPod? podFor(String sessionId) → runtime?.state`.

- [ ] **Step 1: Write the failing test**

Rewrite `client/test/cubits/session/session_pod_test.dart` for the runtime object:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/session_pod.dart';

void main() {
  test('SessionPod runtime mutators bump revision and notify', () {
    var notifications = 0;
    final pod = SessionPod(
      sessionId: 's1',
      workspaceId: 'w1',
      onChanged: () => notifications++,
    );
    expect(pod.state.phase, SessionPhase.idle);

    pod.setPhase(SessionPhase.running);
    expect(pod.state.phase, SessionPhase.running);
    expect(pod.state.revision, 1);
    expect(notifications, 1);

    pod.setPhase(SessionPhase.running); // no-op keeps revision
    expect(pod.state.revision, 1);
    expect(notifications, 1);
  });

  test('per-session isolation: mutating one pod leaves another untouched', () {
    final a = SessionPod(sessionId: 'a', workspaceId: 'w');
    final b = SessionPod(sessionId: 'b', workspaceId: 'w');
    a.setPhase(SessionPhase.error);
    a.setLaunchError('boom');
    expect(b.state.phase, SessionPhase.idle);
    expect(b.state.launchError, isNull);
    expect(a.state.launchError, 'boom');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/session/session_pod_test.dart`
Expected: FAIL to compile — `SessionPod` no longer has `copyWith`.

- [ ] **Step 3: Implement**

Rewrite `client/lib/cubits/session/session_pod.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../chat/model/session_workbench_view.dart';
import 'session_phase.dart';

/// Immutable projection of a session pod's observable state. Selectors bind to
/// [revision] so unchanged pods do not rebuild.
@immutable
class SessionPodState {
  const SessionPodState({
    required this.sessionId,
    required this.workspaceId,
    this.phase = SessionPhase.idle,
    this.launchError,
    this.selectedMemberId = '',
    this.view = SessionWorkbenchView.chat,
    this.revision = 0,
  });

  final String sessionId;
  final String workspaceId;
  final SessionPhase phase;
  final String? launchError;
  final String selectedMemberId;
  final SessionWorkbenchView view;
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is SessionPodState &&
      other.sessionId == sessionId &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(sessionId, revision);
}

/// Mutable runtime object for ONE open conversation. Owns the pod's observable
/// state and (Phase 2) its HistoryStore. Pure-Dart; the host (ChatCubit) is
/// notified through [onChanged] so it can emit stateVersion bumps.
class SessionPod {
  SessionPod({
    required this.sessionId,
    required this.workspaceId,
    this.onChanged,
    SessionPodState? initial,
  }) : _state = initial ??
            SessionPodState(sessionId: sessionId, workspaceId: workspaceId);

  final String sessionId;
  final String workspaceId;
  final void Function()? onChanged;

  SessionPodState _state;
  SessionPodState get state => _state;

  void setPhase(SessionPhase phase) {
    if (_state.phase == phase) return;
    _state = _state.copyWith(phase: phase);
    onChanged?.call();
  }

  void setLaunchError(String? error) {
    if (_state.launchError == error) return;
    _state = _state.copyWith(
      launchError: error,
      clearLaunchError: error == null,
    );
    onChanged?.call();
  }

  void selectMember(String memberId) {
    if (_state.selectedMemberId == memberId) return;
    _state = _state.copyWith(selectedMemberId: memberId);
    onChanged?.call();
  }

  void setView(SessionWorkbenchView view) {
    if (_state.view == view) return;
    _state = _state.copyWith(view: view);
    onChanged?.call();
  }
}
```

`SessionPodState.copyWith` keeps the phase/revision bumping logic from the old value type (revision bumps only on a real field change).

In `client/lib/cubits/chat_cubit.dart`, replace the pod registry:

```dart
final Map<String, SessionPod> _pods = {};

@override
SessionPod? podRuntime(String sessionId) => _pods[sessionId.trim()];

@override
SessionPod? ensurePodRuntime(String sessionId) =>
    _pods.putIfAbsent(sessionId.trim(), () {
      final tab = _tabStore.openTabBySessionId(sessionId.trim());
      return SessionPod(
        sessionId: sessionId.trim(),
        workspaceId: tab?.workspaceId ?? '',
        onChanged: () => _bumpPodRevision(sessionId.trim()),
      );
    });

/// Value of the pod for [sessionId], or null.
SessionPodState? podFor(String sessionId) => _pods[sessionId.trim()]?.state;

SessionPodState? get activePod {
  final id = state.activeSessionId;
  if (id == null || id.isEmpty) return null;
  return _pods[id]?.state;
}

void _bumpPodRevision(String sessionId) {
  if (isClosed) return;
  emit(state.copyWith(stateVersion: state.stateVersion + 1));
}
```

The `ChatConnectStateMixin` now drives the runtime pod directly:

```dart
void _phaseInto(SessionPod? pod, SessionPhase phase) {
  if (pod == null) return;
  pod.setPhase(phase);
}
```

and `beginSessionConnect`/`finishSessionConnect`/`failSessionConnect` use `ensurePodRuntime`/`podRuntime` and `pod.setPhase(...)` / `pod.setLaunchError(...)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/cubits/session/session_pod_test.dart test/cubits/session/session_phase_drive_test.dart test/cubits/chat_cubit_pod_registry_test.dart`
Expected: PASS. Update `session_phase_drive_test.dart` / `chat_cubit_pod_registry_test.dart` to the new API (`podFor` returns `SessionPodState`, not `SessionPod`; use `podRuntime` for runtime ops).

- [ ] **Step 5: Run the affected chat suite**

Run: `cd client && flutter test test/cubits/chat_cubit_test.dart test/cubits/chat_cubit_simple_working_test.dart test/cubits/session/ test/pages/chat/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/session/session_pod.dart client/lib/cubits/chat_cubit.dart client/lib/cubits/chat/chat_connect_state_mixin.dart client/test/cubits/session/session_pod_test.dart client/test/cubits/session/session_phase_drive_test.dart client/test/cubits/chat_cubit_pod_registry_test.dart
git commit -m "refactor(session): SessionPod becomes a runtime object owning its state

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Phase 2 — Pod-owned HistoryStore

### Task 2: `HistoryStore` per-session, member-partitioned

**Files:**
- Create: `client/lib/cubits/session/history_store.dart`
- Test: `client/test/cubits/session/history_store_test.dart`

**Interfaces:**
- Consumes: `AiHistorySeat` (existing), `AiHistoryLoader`, `LoggedMessage` mailbox loader.
- Produces: `class HistoryStore { HistoryStore({required AiHistoryLoader loader, Future<List<LoggedMessage>> Function(String,String)? loadMailboxRecords}); AiHistorySeat memberSeat(String sessionId, String memberId); void disposeSeats(String sessionId); }` — owns the seat map per session, keyed by `historySeatKey(sessionId, memberId)`; forwards seed-pending/lifecycle.

- [ ] **Step 1: Write the failing test**

Create `client/test/cubits/session/history_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/history_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/models/runtime_target.dart';

import '../../support/fake_ai_history_registry.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  late HistoryStore store;

  setUp(() {
    setUpTestAppStorage();
    store = HistoryStore(
      loader: AiHistoryLoader(
        contextBuilder: const SessionHistoryContextBuilder(),
        resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
          target: RuntimeTarget.local(),
          filesystem: LocalFilesystem(),
          home: '/tmp/history-store',
          cwd: '/tmp/history-store',
          appDataRoot: '/tmp/history-store',
          paths: AppPaths('/tmp/history-store'),
        ),
        registry: fakeAiHistoryRegistry(
          cli: CliTool.claude,
          adapter: _FakeAdapter(),
        ),
      ),
    );
  });

  tearDown(() {
    tearDownTestAppStorage();
  });

  test('memberSeat is per (session, member) and stable', () {
    final a = store.memberSeat('s1', '');
    final a2 = store.memberSeat('s1', '');
    final b = store.memberSeat('s1', 'member-x');
    expect(identical(a, a2), isTrue);
    expect(identical(a, b), isFalse);
  });

  test('disposeSeats closes seats for a session', () async {
    final seat = store.memberSeat('s1', '');
    expect(seat.isClosed, isFalse);
    await store.disposeSeats('s1');
    expect(seat.isClosed, isTrue);
  });
}
```

(`_FakeAdapter implements AiTranscriptAdapter` as in the earlier tests.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/session/history_store_test.dart`
Expected: FAIL to compile — `HistoryStore` does not exist.

- [ ] **Step 3: Implement**

Create `client/lib/cubits/session/history_store.dart`:

```dart
import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';

import '../../services/session/ai_history_loader.dart';
import '../../services/session/history_seat_key.dart';
import '../../services/team_bus/persistence/bus_message_log.dart';
import '../ai_history_seat.dart';

/// Per-session history store: one [AiHistorySeat] per `memberId`, owned by a
/// single session. The pod (Phase 1) owns one of these; SessionChatView binds a
/// member seat through it instead of the global AiHistoryCubit registry.
class HistoryStore {
  HistoryStore({
    required AiHistoryLoader loader,
    Future<List<LoggedMessage>> Function(String sessionId, String memberId)?
    loadMailboxRecords,
  }) : _loader = loader,
       _loadMailboxRecords = loadMailboxRecords;

  final AiHistoryLoader _loader;
  final Future<List<LoggedMessage>> Function(String sessionId, String memberId)?
  _loadMailboxRecords;
  final Map<String, AiHistorySeat> _seats = {};
  final Map<String, StreamSubscription<AiHistoryState>> _seatSubs = {};

  AiHistoryLoader get loader => _loader;

  AiHistorySeat memberSeat({required String sessionId, required String memberId}) {
    final key = historySeatKey(sessionId: sessionId, selectedMemberId: memberId);
    final existing = _seats[key];
    if (existing != null) return existing;
    final seat = AiHistorySeat(
      loader: _loader,
      loadMailboxRecords: _loadMailboxRecords,
    );
    _seats[key] = seat;
    // Keep seat emits reachable to any host listening directly; the seat's own
    // stream is the channel (SessionChatView binds it directly).
    _seatSubs[key] = seat.stream.listen((_) {});
    return seat;
  }

  AiHistorySeat? seatOf({required String sessionId, required String memberId}) {
    final key = historySeatKey(sessionId: sessionId, selectedMemberId: memberId);
    return _seats[key];
  }

  Future<void> disposeSeats(String sessionId) async {
    final prefix = '${sessionId.trim()}|';
    final keys = _seats.keys.where((k) => k.startsWith(prefix)).toList();
    for (final key in keys) {
      final sub = _seatSubs.remove(key);
      await sub?.cancel();
      final seat = _seats.remove(key);
      await seat?.close();
    }
  }

  Future<void> close() async {
    for (final key in _seats.keys.toList()) {
      final sub = _seatSubs.remove(key);
      await sub?.cancel();
      final seat = _seats.remove(key);
      await seat?.close();
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/cubits/session/history_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/session/history_store.dart client/test/cubits/session/history_store_test.dart
git commit -m "feat(session): per-session HistoryStore with member-partitioned seats

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Task 3: `SessionPod` owns a `HistoryStore`; SessionChatView binds through it

**Files:**
- Modify: `client/lib/cubits/session/session_pod.dart` (add `HistoryStore history`)
- Modify: `client/lib/pages/chat/session_chat_view.dart` (`_bindSeat` + `loader` access)
- Test: `client/test/cubits/session/session_pod_history_test.dart`

**Interfaces:**
- Consumes: `HistoryStore` (Task 2), `SessionPod` runtime (Task 1).
- Produces: `SessionPod.history` — the pod's `HistoryStore`; `SessionChatView._bindSeat` resolves the member seat from `chatCubit.podRuntime(sessionId).history.memberSeat(...)`.

- [ ] **Step 1: Write the failing test**

Create `client/test/cubits/session/session_pod_history_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/session_pod.dart';

void main() {
  test('SessionPod owns a HistoryStore and exposes member seats', () {
    final pod = SessionPod(sessionId: 's1', workspaceId: 'w1');
    final seatA = pod.history.memberSeat(sessionId: 's1', memberId: '');
    final seatB = pod.history.memberSeat(sessionId: 's1', memberId: 'm');
    expect(identical(seatA, pod.history.memberSeat(sessionId: 's1', memberId: '')), isTrue);
    expect(identical(seatA, seatB), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/session/session_pod_history_test.dart`
Expected: FAIL — `SessionPod` has no `history` (and its constructor does not yet create one).

- [ ] **Step 3: Implement**

In `session_pod.dart`, give the pod a `HistoryStore`:

```dart
import 'history_store.dart';
// ...
class SessionPod {
  SessionPod({
    required this.sessionId,
    required this.workspaceId,
    this.onChanged,
    SessionPodState? initial,
    HistoryStore? history,
  })  : _state = initial ??
            SessionPodState(sessionId: sessionId, workspaceId: workspaceId),
        history = history ?? HistoryStore(loader: _defaultHistoryLoader());
  // ...
  final HistoryStore history;
}
```

Where `_defaultHistoryLoader()` is a minimal `AiHistoryLoader` constructed with the same work-context resolver used elsewhere (see `ai_history_cubit_test.dart` for the resolver shape); the pod accepts an injected loader for tests. If wiring a real loader at pod construction is not yet possible (the loader needs a work-plane `RuntimeContext` resolver), make `history` nullable and create it lazily via a `HistoryStore Function()? historyFactory` — the pod test passes a factory that builds a `HistoryStore` with a stub loader.

In `session_chat_view.dart`, replace `_bindSeat`:

```dart
void _bindSeat() {
  final chat = context.read<ChatCubit>();
  final pod = chat.podRuntime(widget.session.sessionId);
  final store = pod?.history;
  _seat = store != null
      ? store.memberSeat(
          sessionId: widget.session.sessionId,
          memberId: widget.selectedMemberId,
        )
      : context.read<AiHistoryCubit>().ensureSeat(
          sessionId: widget.session.sessionId,
          selectedMemberId: widget.selectedMemberId,
        );
}
```

and the live-refresh `loader` access (`session_chat_view.dart:445-471`) falls back to the pod's store loader when available:

```dart
final history = chat.podRuntime(widget.session.sessionId)?.history;
final loader = history?.loader ?? context.read<AiHistoryCubit>().loader;
```

(`history?.loader` is `AiHistoryLoader`; the fallback keeps `AiHistoryCubit` working until it is retired.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/cubits/session/session_pod_history_test.dart`
Expected: PASS.

- [ ] **Step 5: Run chat page tests**

Run: `cd client && flutter test test/pages/chat/ test/cubits/ai_history_cubit_test.dart test/cubits/chat_cubit_test.dart`
Expected: PASS (the fallback keeps the global cubit path working).

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/session/session_pod.dart client/lib/pages/chat/session_chat_view.dart client/test/cubits/session/session_pod_history_test.dart
git commit -m "feat(session): pod owns HistoryStore; SessionChatView binds via pod

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Task 4: Retire the global seat registry from `AiHistoryCubit`

**Files:**
- Modify: `client/lib/cubits/ai_history_cubit.dart`
- Test: existing `ai_history_cubit_test.dart`, `ai_history_seat_isolation_test.dart`

**Interfaces:**
- Consumes: `HistoryStore` (Task 2).
- Produces: `AiHistoryCubit` becomes a facade: `loader`, `ensureSeat` delegates to a per-session store registry (keyed by sessionId) for the legacy callers, or is removed once all callers bind via pods.

- [ ] **Step 1: Survey callers**

Run: `cd client && grep -rn "ensureSeat\|seedPendingUser\|cancelSeedPendingUser\|disposeSeatsForSession\|\.load(" lib/ test/ --include="*.dart" | grep -i history`
Expected: list of remaining `AiHistoryCubit` consumers (sidebar presence, mailbox, tests).

- [ ] **Step 2: Move `seedPendingUser`/`cancelSeedPendingUser`/lifecycle into `HistoryStore`**

Add to `history_store.dart` (mirroring `AiHistoryCubit` semantics):

```dart
  /// Landing create+send may finish before History loads the new seat.
  final Map<String, String> _seedPendingByKey = {};

  void seedPendingUser({
    required String sessionId,
    required String memberId,
    required String text,
  }) {
    final key = historySeatKey(sessionId: sessionId, selectedMemberId: memberId);
    final seat = _seats[key];
    if (seat != null && _seatMatchesKey(seat, key)) {
      seat.enqueuePendingUser(text.trim());
      _seedPendingByKey.remove(key);
      return;
    }
    _seedPendingByKey[key] = text.trim();
  }

  void _consumeSeedPending(String sessionId, String memberId) { /* onTranscriptApplied */ }

  void cancelSeedPendingUser({required String sessionId, required String text}) { /* mirror */ }
```

Wire `memberSeat`'s `onTranscriptApplied` to `_consumeSeedPending`.

- [ ] **Step 3: Point the landing/workspace callers at the pod's store**

Modify `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart` (and any other caller) so `seedPendingUser`/`cancelSeedPendingUser` go through `chatCubit.podRuntime(sessionId).history` instead of `aiHistoryCubit`.

- [ ] **Step 4: Run the history + chat test suites**

Run: `cd client && flutter test test/cubits/ai_history_cubit_test.dart test/cubits/ai_history_seat_isolation_test.dart test/cubits/ai_history_seat_working_sync_test.dart test/cubits/chat_cubit_test.dart test/pages/home_workspace/workspace/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/ai_history_cubit.dart client/lib/cubits/session/history_store.dart client/lib/pages/home_workspace/workspace/workspace_session_actions.dart
git commit -m "refactor(history): seed/lifecycle move to HistoryStore; AiHistoryCubit slims

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Phase 3 — Thin ChatCubit (pod replaces ChatTab runtime)

> Scope note: this is the largest phase. The plan is ordered so the first tasks are independently shippable and the pod becomes the per-session runtime progressively. If this balloons, checkpoint after Task 6.

### Task 5: `ChatCubit` registry returns runtime pods; keep `tabStore` for the launch machinery

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart`
- Test: `client/test/cubits/chat_cubit_pod_registry_test.dart`

**Interfaces:**
- Produces: `ChatCubit.podRuntime(String sessionId)`, `ensurePodRuntime`, `podFor`, `activePod` all finalized (Task 1). The registry is the single source of per-session runtime for UI.

- [ ] **Step 1: Write the failing test (registry + lifecycle)**

Add to `chat_cubit_pod_registry_test.dart`:

```dart
test('ensurePodRuntime creates a pod and closeSession disposes its history', () async {
  final pod = cubit.ensurePodRuntime('s1');
  expect(cubit.podFor('s1')!.sessionId, 's1');
  final seat = pod.history.memberSeat(sessionId: 's1', memberId: '');
  // Simulate session close: dispose pod history.
  await pod.history.disposeSeats('s1');
  expect(seat.isClosed, isTrue);
});
```

- [ ] **Step 2: Run test to verify it fails / passes**

Run: `cd client && flutter test test/cubits/chat_cubit_pod_registry_test.dart`
Expected: FAIL if `closeSession`/pod lifecycle not wired; wire `ChatCubit.closeTab`/`deleteSession` to dispose the pod's history.

- [ ] **Step 3: Wire pod disposal into session close**

In `chat_cubit.dart::closeTab`/`_tearDownTab`/`deleteSession`, after the tab is removed, `await podRuntime(sessionId)?.history.disposeSeats(sessionId)` and drop the pod from `_pods`.

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/cubits/chat_cubit_test.dart test/cubits/chat_cubit_simple_working_test.dart test/cubits/chat_cubit_pod_registry_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/chat_cubit.dart client/test/cubits/chat_cubit_pod_registry_test.dart
git commit -m "feat(session): pod lifecycle tied to session close

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Task 6: Sidebar/workbench read pod state for phase/chrome

**Files:**
- Modify: `client/lib/widgets/sidebar_session_tile.dart` (working/spinner from pod phase)
- Modify: `client/lib/pages/chat_workbench.dart` (already reads pod phase — confirm)

**Interfaces:**
- Consumes: `ChatCubit.podFor(String)` (Task 1/5).
- Produces: sidebar "starting" spinner derives from `podFor(sessionId)?.phase.isLaunching` instead of `sessionConnectingId`.

- [ ] **Step 1: Write the failing test**

In `client/test/widgets/sidebar_session_tile_test.dart` (or a new test), assert that a session whose pod is `connecting` shows the starting indicator:

```dart
// pump SidebarSessionTile with a ChatCubit whose podFor(sid) returns a
// connecting state; expect the starting spinner, not the idle dot.
```

- [ ] **Step 2: Implement**

In `sidebar_session_tile.dart`, replace the `sessionConnectingId`-based starting check with `chat.podFor(sessionId)?.phase.isLaunching ?? false`.

- [ ] **Step 3: Run tests**

Run: `cd client && flutter test test/widgets/ test/pages/chat/`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add client/lib/widgets/sidebar_session_tile.dart
git commit -m "refactor(sidebar): starting indicator from pod phase

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Task 7 (checkpoint): remaining thin-ChatCubit sweep

After Task 6, survey remaining `state.tabs` / `tabStore` consumers in `pages/`, `widgets/`, `cubits/` and decide — with the user — whether to continue collapsing `ChatTabStore` into pods in this effort or land a checkpoint. This is a deliberate checkpoint task: do NOT attempt the full sweep silently.

---

## Self-review notes

- **Spec coverage:** pod-owned HistoryStore (Tasks 2-4), thin ChatCubit (Tasks 5-7), runtime pod (Task 1). Cache-first/no-blank and per-session phase already landed.
- **Risk:** Task 3's `SessionPod` needs a `HistoryStore` but the loader needs a work-context resolver; the plan allows a lazy `historyFactory` so pod construction stays test-friendly. Task 4's retirement depends on caller survey — if too many callers remain, keep `AiHistoryCubit` as a facade and only move the landing path.
- **Phase 3 is large:** Tasks 5-7 are the shippable foundation; the full tab→pod collapse is checkpointed at Task 7 rather than hidden.
