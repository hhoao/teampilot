# Composer Surface Wait Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Landing and History continue wait for the CLI input box (composer / boot-frame) while the PTY is alive, instead of failing at a fixed 120s, and fail fast if the process dies.

**Architecture:** Extract a tiny wait-policy helper (dead-shell + 10-minute cap). `TabMemberMaterializer.ensureMemberInputReady` uses it inside the existing 100ms poll. Call sites drop `.timeout(120s)` and catch `MemberInputReadyException`. Composer needles and `isBootFrameReady` stay unchanged. Workspace `--add-dir` / extra folders are out of scope.

**Tech Stack:** Dart / Flutter (`package:teampilot`), `flutter_test`

## Global Constraints

- Do not treat empty/ANSI-only PTY as boot-frame ready.
- Do not paste into a black or splash screen.
- Production wait cap is 10 minutes; tests inject a short cap.
- Do not change `--add-dir`, plugin loading, or isolated HOME seeding.
- Do not invent a second inject path.

---

### Task 1: Wait-policy helper

**Files:**
- Create: `client/lib/cubits/chat/member_input_ready_wait.dart`
- Test: `client/test/cubits/chat/member_input_ready_wait_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `const Duration defaultMemberInputReadyCap = Duration(minutes: 10)`
  - `enum MemberInputReadyFailure { dead, timedOut }`
  - `class MemberInputReadyException implements Exception { final MemberInputReadyFailure failure; }`
  - `class MemberShellReadySnapshot { startFailed, isConnecting, isRunning, isConnected }`
  - `bool memberInputWaitSawRunning(MemberShellReadySnapshot shell)`
  - `bool memberInputWaitShouldAbortDead({required MemberShellReadySnapshot shell, required bool sawRunning})`
  - `bool memberInputWaitTimedOut({required DateTime startedAt, required Duration cap, required DateTime now})`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/member_input_ready_wait.dart';

void main() {
  const running = MemberShellReadySnapshot(
    startFailed: false,
    isConnecting: false,
    isRunning: true,
    isConnected: true,
  );
  const idle = MemberShellReadySnapshot(
    startFailed: false,
    isConnecting: false,
    isRunning: false,
    isConnected: false,
  );
  const failed = MemberShellReadySnapshot(
    startFailed: true,
    isConnecting: false,
    isRunning: false,
    isConnected: false,
  );

  test('idle shell that never ran is not dead', () {
    expect(
      memberInputWaitShouldAbortDead(shell: idle, sawRunning: false),
      isFalse,
    );
  });

  test('startFailed is dead even if it never ran', () {
    expect(
      memberInputWaitShouldAbortDead(shell: failed, sawRunning: false),
      isTrue,
    );
  });

  test('process that ran then went idle is dead', () {
    expect(
      memberInputWaitShouldAbortDead(shell: idle, sawRunning: true),
      isTrue,
    );
  });

  test('running shell is not dead', () {
    expect(
      memberInputWaitShouldAbortDead(shell: running, sawRunning: true),
      isFalse,
    );
  });

  test('default cap is 10 minutes', () {
    expect(defaultMemberInputReadyCap, const Duration(minutes: 10));
  });

  test('cap fires after waitCap elapses', () {
    final started = DateTime(2026, 8, 20, 11, 14, 57);
    expect(
      memberInputWaitTimedOut(
        startedAt: started,
        cap: const Duration(minutes: 10),
        now: started.add(const Duration(minutes: 10)),
      ),
      isTrue,
    );
    expect(
      memberInputWaitTimedOut(
        startedAt: started,
        cap: const Duration(minutes: 10),
        now: started.add(const Duration(seconds: 120)),
      ),
      isFalse,
    );
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart test test/cubits/chat/member_input_ready_wait_test.dart`

Expected: FAIL — library not found.

- [ ] **Step 3: Write minimal implementation**

Create `member_input_ready_wait.dart` with the types and functions above.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart test test/cubits/chat/member_input_ready_wait_test.dart`

Expected: PASS

- [ ] **Step 5: Commit** — skip unless the user asks.

---

### Task 2: Waiter uses death + cap

**Files:**
- Modify: `client/lib/services/terminal/terminal_session.dart` — expose `startFailed`
- Modify: `client/lib/cubits/chat/tab_member_materializer.dart`
- Test: `client/test/cubits/chat/tab_member_composer_surface_test.dart`

**Interfaces:**
- Consumes: helper from Task 1
- Produces: `ensureMemberInputReady(..., {Duration waitCap = defaultMemberInputReadyCap})` throws `MemberInputReadyException` on dead/cap

- [ ] **Step 1: Write failing tests on the composer harness**

Add two tests (do **not** latch boot frame for these):

1. Running shell, no composer paint, `waitCap: 200ms` → throws `MemberInputReadyException(timedOut)` and does not take ~120s.
2. Connected shell then `session.input`/`failLaunch` equivalent: call `_launch.failLaunch` via a new `TerminalSession` test hook or public `failLaunch`. After fail, waiter throws `dead` well under the cap.

Expose `bool get startFailed => _launch.startFailed;` and `void failLaunch(String message) => _launch.failLaunch(message);` on `TerminalSession`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart test test/cubits/chat/tab_member_composer_surface_test.dart`

Expected: FAIL — `waitCap` not accepted / no exception.

- [ ] **Step 3: Implement poll-loop checks**

Inside `ensureMemberInputReady` after `materializeMember`:

```dart
final startedAt = DateTime.now();
var sawRunning = false;
// in loop, after tab-null checks:
final shell = tab.memberShells[memberId];
if (shell != null) {
  final snap = MemberShellReadySnapshot(
    startFailed: shell.startFailed,
    isConnecting: shell.isConnecting,
    isRunning: shell.isRunning,
    isConnected: shell.isConnected,
  );
  if (memberInputWaitSawRunning(snap)) sawRunning = true;
  if (memberInputWaitShouldAbortDead(shell: snap, sawRunning: sawRunning)) {
    appLogger.d('[member-materializer] input-ready dead ...');
    throw const MemberInputReadyException(MemberInputReadyFailure.dead);
  }
}
if (memberInputWaitTimedOut(
      startedAt: startedAt,
      cap: waitCap,
      now: DateTime.now(),
    )) {
  appLogger.d('[member-materializer] input-ready composer wait cap ...');
  throw const MemberInputReadyException(MemberInputReadyFailure.timedOut);
}
```

Do not send CR unless existing `maybeNudgeMemberBootGate` boot-gate needles match.

- [ ] **Step 4: Run tests**

Run: `cd client && dart test test/cubits/chat/tab_member_composer_surface_test.dart test/cubits/chat/tab_member_materializer_test.dart`

Expected: PASS

- [ ] **Step 5: Commit** — skip unless the user asks.

---

### Task 3: Landing + History continue drop 120s timeout

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`
- Modify: `client/lib/pages/chat/session_history_review_submit.dart`
- Modify: `client/test/pages/chat/session_history_review_submit_test.dart`

**Interfaces:**
- Consumes: `MemberInputReadyException`, `defaultMemberInputReadyCap`
- Produces: landing `_ensureLandingSessionConnected` returns false on exception (log `composer wait cap` vs dead); History `readyTimeout` default `defaultMemberInputReadyCap`

- [ ] **Step 1: Update History continue test**

Change `keeps failure when member never becomes ready` to throw `MemberInputReadyException(MemberInputReadyFailure.timedOut)` instead of `TimeoutException`. Keep `readyTimeout` injectable; default must be 10 minutes (assert in a small test or by reading the default).

- [ ] **Step 2: Run to see timeout-catch still expects TimeoutException (fail) or pass if we update catch first**

- [ ] **Step 3: Wire call sites**

Landing:

```dart
try {
  await chatCubit.memberMaterializer.ensureMemberInputReady(
    session.sessionId,
    memberId,
    directToPty: true,
  );
  return true;
} on MemberInputReadyException catch (error) {
  appLogger.w(
    'submitWorkspaceLandingMessage: ${error.failure == MemberInputReadyFailure.timedOut ? 'composer wait cap' : 'composer wait dead'} '
    'session=${session.sessionId} member=$memberId',
  );
  return false;
}
```

History continue: `await ensureMemberInputReady(..., waitCap: readyTimeout)` with default `defaultMemberInputReadyCap`. Catch `MemberInputReadyException` instead of `TimeoutException`. Callback type must add `{Duration waitCap = defaultMemberInputReadyCap}` — or keep the callback as `Future<void> Function(...)` and let ChatCubit/materializer own the default cap so History just stops wrapping `.timeout`. Prefer **not** changing the callback signature: History continue passes nothing; materializer default is 10 minutes. Tests that need a 1ms cap call materializer directly, not History continue's `readyTimeout`.

**Simplify:** Remove History `readyTimeout` / `.timeout` entirely. The 1ms test becomes: stub `ensureMemberInputReady` still throws `MemberInputReadyException`. Production History uses materializer default cap.

- [ ] **Step 4: Run tests**

Run:

```
cd client && dart test \
  test/pages/chat/session_history_review_submit_test.dart \
  test/cubits/chat/tab_member_composer_surface_test.dart \
  test/cubits/chat/member_input_ready_wait_test.dart
```

Expected: PASS

- [ ] **Step 5: Commit** — skip unless the user asks.
