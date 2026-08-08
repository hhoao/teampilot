# Thin ChatCubit slice: replace `sessionConnectingId`/'pending' with pod-phase concurrency gate

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `ChatState.sessionConnectingId` and the `'pending'` sentinel. The launch concurrency gate and all readers switch to the per-session pod phase (`isSessionConnecting`), with a dedicated materializing flag for the pre-session `'pending'` case. This shrinks `ChatState` (thin ChatCubit) and kills the last global connect sentinel.

**Architecture:** `SessionLaunchHost` gains three narrow methods — `isSessionConnecting(sessionId)` (pod `phase.isLaunching`), `hasConnectingSession` (any pod launching OR materialization in flight), and `setMaterializingInFlight(bool)` (the former `'pending'`). The `ChatConnectStateMixin` routes `begin/finish/failSessionConnect('pending')` through the materializing flag; real session ids drive the pod phase. `ChatState.sessionConnectingId` and `ChatWorkbenchSlice.sessionConnectingId` are deleted; the structural signal and chat-view rebuild triggers rely on `stateVersion` (which pod changes already bump).

**Tech Stack:** Flutter / flutter_bloc. Link-chain tests via the existing `chat_cubit_simple_working_test.dart` harness (real launch pipeline → connect → finish).

## Global Constraints

- Preserve launch concurrency semantics exactly: a connect in flight (any session, including pre-materialization) must serialize a second connect; `isMemberConnectOwnedElsewhere` must still gate the per-member PTY connect.
- Follow the SessionPod spec; keep existing behavior.
- Every task ends green: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test <target>`.
- Commit after each task.

---

### Task 1: Host port methods + mixin routing (remove the `'pending'` pod)

**Files:**
- Modify: `client/lib/cubits/chat/session_launch_host.dart` (`SessionConnectStatePort`/`SessionLaunchHost`)
- Modify: `client/lib/cubits/chat/chat_connect_state_mixin.dart`
- Modify: `client/lib/cubits/chat_cubit.dart` (implement + `_materializingInFlight`)
- Test: `client/test/cubits/session/session_phase_drive_test.dart` (add materializing cases)

**Interfaces:**
- Produces: `bool isSessionConnecting(String sessionId)`, `bool get hasConnectingSession`, `void setMaterializingInFlight(bool)` on `SessionLaunchHost`.

- [ ] **Step 1: Write the failing test**

Add to `client/test/cubits/session/session_phase_drive_test.dart`:

```dart
  test('pending materialization sets hasConnectingSession without a real pod', () {
    cubit.beginSessionConnect('pending');
    expect(cubit.hasConnectingSession, isTrue);
    expect(cubit.podFor('pending'), isNull, reason: 'no real pod for pending');
    cubit.finishSessionConnect('pending');
    expect(cubit.hasConnectingSession, isFalse);
  });

  test('isSessionConnecting follows a real session pod phase', () {
    cubit.ensurePodRuntime('s1');
    expect(cubit.isSessionConnecting('s1'), isFalse);
    cubit.beginSessionConnect('s1');
    expect(cubit.isSessionConnecting('s1'), isTrue);
    cubit.finishSessionConnect('s1');
    expect(cubit.isSessionConnecting('s1'), isFalse);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/session/session_phase_drive_test.dart`
Expected: FAIL — `hasConnectingSession`/`isSessionConnecting` not defined.

- [ ] **Step 3: Implement**

In `session_launch_host.dart` `SessionConnectStatePort`, add:

```dart
  /// True when [sessionId]'s pod is still provisioning/connecting.
  bool isSessionConnecting(String sessionId);
  /// True when any session is connecting or pre-session materialization is in flight.
  bool get hasConnectingSession;
  /// Marks pre-session materialization (former `'pending'`) in flight.
  void setMaterializingInFlight(bool value);
```

In `chat_cubit.dart`:

```dart
  bool _materializingInFlight = false;

  @override
  bool isSessionConnecting(String sessionId) =>
      podRuntime(sessionId)?.state.phase.isLaunching ?? false;

  @override
  bool get hasConnectingSession =>
      _materializingInFlight ||
      _pods.values.any((p) => p.state.phase.isLaunching);

  @override
  void setMaterializingInFlight(bool value) => _materializingInFlight = value;
```

In `chat_connect_state_mixin.dart`, rewrite `beginSessionConnect`/`finishSessionConnect`/`failSessionConnect` and drop the connecting-id emit:

```dart
  void beginSessionConnect(String sessionId) {
    appLogger.d('[session-launch] connecting start session=$sessionId');
    clearLaunchError(sessionId);
    if (sessionId == 'pending') {
      setMaterializingInFlight(true);
      return;
    }
    ensurePodRuntime(sessionId).setPhase(SessionPhase.connecting);
  }

  void finishSessionConnect(String sessionId) {
    updateTabRunning(sessionId);
    if (isClosed) return;
    if (sessionId == 'pending') {
      setMaterializingInFlight(false);
      return;
    }
    podRuntime(sessionId)?.setPhase(SessionPhase.running);
  }

  void failSessionConnect(String sessionId, String rawMessage) {
    appLogger.w(
      '[session-launch] connecting failed session=$sessionId: $rawMessage',
    );
    setLaunchError(sessionId, rawMessage);
    if (sessionId == 'pending') {
      setMaterializingInFlight(false);
      updateTabRunning(sessionId);
      return;
    }
    final pod = podRuntime(sessionId);
    if (pod != null) {
      pod.setPhase(SessionPhase.error);
      pod.setLaunchError(rawMessage);
    }
    updateTabRunning(sessionId);
  }
```

Remove `_clearConnectingIdIfMatch` and the `state.sessionConnectingId` reads in the mixin.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/cubits/session/session_phase_drive_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/chat/session_launch_host.dart client/lib/cubits/chat/chat_connect_state_mixin.dart client/lib/cubits/chat_cubit.dart client/test/cubits/session/session_phase_drive_test.dart
git commit -m "feat(session): pod-phase connect gate — pending no longer creates a pod

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Task 2: Migrate launch-machinery readers off `sessionConnectingId`

**Files:**
- Modify: `client/lib/services/launch/session_launch_pipeline.dart`
- Modify: `client/lib/services/launch/session_tab_surface_coordinator.dart`
- Modify: `client/lib/services/launch/session_launch_connect_prep_runner.dart`
- Modify: `client/lib/services/launch/session_member_connect_scheduler.dart`
- Modify: `client/lib/services/launch/session_shell_connector.dart`
- Modify: `client/lib/cubits/chat/session_launch_service.dart`
- Test: link-chain — `client/test/cubits/chat_cubit_simple_working_test.dart` + `client/test/services/launch/session_tab_surface_coordinator_test.dart`

**Interfaces:**
- Consumes: `SessionLaunchHost.isSessionConnecting`/`hasConnectingSession` (Task 1).
- Produces: no lib code reads `sessionConnectingId` outside the state field.

- [ ] **Step 1: Add link-chain coverage (failing or baseline)**

Add a test to `chat_cubit_simple_working_test.dart` that opens a session with `connectImmediately: true` and asserts the pod reaches `running` and no second connect is scheduled during the in-flight window. Run it first to confirm it passes on the current code (baseline), then keep it green through the migration.

- [ ] **Step 2: Migrate each reader**

- `session_launch_pipeline.dart:274` `if (_state().sessionConnectingId != null)` → `if (_host.hasConnectingSession)`.
- `session_tab_surface_coordinator.dart:89` `connectAlreadyScheduled = state.sessionConnectingId == session.sessionId` → `_host.isSessionConnecting(session.sessionId)`.
- `session_launch_connect_prep_runner.dart:189,202` → `_host.isSessionConnecting(launchSession.sessionId)`.
- `session_member_connect_scheduler.dart:126` `ownsConnectToken = state.sessionConnectingId != tab.info.id` → `_host.hasConnectingSession && !_host.isSessionConnecting(tab.info.id)`.
- `session_shell_connector.dart:99` → `_host.isSessionConnecting(tab.info.id)`.
- `session_launch_service.dart:606` `isMemberConnectOwnedElsewhere` → `_host.isSessionConnecting(sessionId)`.

- [ ] **Step 3: Run tests**

Run: `cd client && flutter test test/services/launch/ test/cubits/chat_cubit_simple_working_test.dart test/cubits/chat_cubit_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/launch/ client/lib/cubits/chat/session_launch_service.dart client/test/cubits/chat_cubit_simple_working_test.dart
git commit -m "refactor(launch): concurrency gate reads pod phase, not sessionConnectingId

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Task 3: Remove `sessionConnectingId` from ChatState, slice, and UI signals

**Files:**
- Modify: `client/lib/cubits/chat/model/chat_state.dart`
- Modify: `client/lib/pages/chat/chat_workbench_slice.dart`
- Modify: `client/lib/pages/chat/chat_scoped_tab_view.dart`
- Modify: `client/lib/pages/chat/chat_page_structural_signal.dart`
- Modify: `client/lib/pages/workbench/workbench_body.dart`
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Test: `client/test/pages/chat/chat_workbench_slice_test.dart`, `client/test/cubits/chat_cubit_test.dart` (remove `isActiveSessionConnecting` assertions), `client/test/pages/chat/chat_page_structural_signal_test.dart`

**Interfaces:**
- Produces: no `sessionConnectingId` field on `ChatState`/`ChatWorkbenchSlice`; the structural signal's connecting part derives from pod phase or drops (stateVersion covers it).

- [ ] **Step 1: Write the failing test**

In `client/test/pages/chat/chat_workbench_slice_test.dart`, assert the slice no longer carries a `sessionConnectingId` field (compile-level: the test referencing it fails). Update the `ChatState.isActiveSessionConnecting` group to be removed.

- [ ] **Step 2: Implement**

- `chat_state.dart`: delete `sessionConnectingId` field + `isActiveSessionConnecting` getter.
- `chat_workbench_slice.dart`: delete `sessionConnectingId` field + its constructor arg; update `ChatWorkbenchSlice.from`.
- `chat_scoped_tab_view.dart`: drop the `sessionConnectingId` arg in the background-branch slice.
- `chat_page_structural_signal.dart`: drop `sessionConnectingId` from the signal fields + `_scopedConnectingId`; the signal's equality/stateVersion still triggers on pod-phase emits.
- `workbench_body.dart::_sliceForSession`: drop the `sessionConnectingId` arg.
- `session_chat_view.dart:1271`: remove the `previous.sessionConnectingId != current.sessionConnectingId` buildWhen clause.

- [ ] **Step 3: Run tests**

Run: `cd client && flutter test test/pages/chat/ test/pages/chat_page_rebuild_test.dart test/cubits/chat_cubit_test.dart test/cubits/chat_cubit_simple_working_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add client/lib/cubits/chat/model/chat_state.dart client/lib/pages/chat/chat_workbench_slice.dart client/lib/pages/chat/chat_scoped_tab_view.dart client/lib/pages/chat/chat_page_structural_signal.dart client/lib/pages/workbench/workbench_body.dart client/lib/pages/chat/session_chat_view.dart client/test/pages/chat/
git commit -m "refactor(chat): remove sessionConnectingId from state, slice, and signals

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Task 4: Link-chain verification + cleanup

**Files:**
- Modify: none (verification).

- [ ] **Step 1: Full launch link-chain run**

Run: `cd client && flutter test test/cubits/chat_cubit_simple_working_test.dart test/cubits/chat_cubit_test.dart test/services/launch/ test/cubits/chat/ test/pages/chat/`
Expected: PASS — the real launch pipeline (open → connect → finish) with the pod-phase gate behaves identically.

- [ ] **Step 2: Grep for leftovers**

Run: `grep -rn "sessionConnectingId\|'pending'" client/lib --include="*.dart"`
Expected: no `sessionConnectingId`; `'pending'` only in the mixin's `sessionId == 'pending'` branches.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore(chat): link-chain green after pod-phase connect gate

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-review notes

- **Semantics preserved:** `hasConnectingSession` covers the `'pending'` materialization window (no real pod); `isSessionConnecting(sid)` is the pod-phase equivalent of `sessionConnectingId == sid`. `isMemberConnectOwnedElsewhere` and the `_runConnect` serialization guard keep their intent.
- **Emit side-effect:** removing the connecting-id emit also removes the double-emit in `begin/finishSessionConnect` — a bonus emit-dedup.
- **Risk:** the structural signal drops `sessionConnectingId`; rebuild triggers rely on `stateVersion` (pod `onChanged` bumps it). The link-chain test in Task 2 covers the launch behavior.
