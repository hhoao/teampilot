# Prevent Lazy Member Auto-Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (recommended) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the current member page stable when a team member is started by a background or lazy-materialization path, while preserving explicit member switching.

**Architecture:** Keep `SessionMemberConnectScheduler.schedule`'s `selectMember` flag as the boundary between shell materialization and member selection. Background materialization callers pass `false`; explicit member-opening callers retain the selecting default. Add regression assertions at the materializer and cubit lazy-restore boundaries.

**Tech Stack:** Flutter/Dart, `flutter_test`, repository test runner, Bloc/Cubit state, injected terminal/session fakes.

## Global Constraints

- Never invoke `flutter test` directly; use `cd client && dart run tool/run_tests.dart ...`.
- Before completion run `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Preserve unrelated existing worktree changes.
- Keep explicit `openMemberTab` behavior unchanged.

---

### Task 1: Lock down non-selecting materialization semantics

**Files:**
- Modify: `client/lib/cubits/chat/tab_member_materializer.dart:345`
- Test: `client/test/cubits/chat/tab_member_materializer_test.dart`

**Interfaces:**
- Consumes: `MemberConnector.scheduleMemberConnect(TeamProfile, TeamMemberConfig, ChatTab, {bool selectMember})`.
- Produces: All `TabMemberMaterializer.materializeMember`-initiated connects call the connector with `selectMember: false`.

- [ ] **Step 1: Extend the recording connector to capture selection intent**

In `_RecordingConnector`, add a nullable `lastSelectMember` field and assign it from the named argument inside `scheduleMemberConnect`:

```dart
bool? lastSelectMember;

@override
void scheduleMemberConnect(
  TeamProfile team,
  TeamMemberConfig member,
  ChatTab tab, {
  bool selectMember = true,
}) {
  scheduleCalls++;
  lastMemberId = member.id;
  lastSelectMember = selectMember;
}
```

- [ ] **Step 2: Add the failing assertion to the existing numbered-roster materialization test**

After the existing `lastMemberId` assertion in `materialize resolves numbered instance ids from session roster`, add:

```dart
expect(connector.lastSelectMember, isFalse);
```

- [ ] **Step 3: Run the focused test and verify it fails for the missing flag**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/tab_member_materializer_test.dart --plain-name "materialize resolves numbered instance ids from session roster"`

Expected: FAIL because the materializer currently invokes the connector without `selectMember: false`, so the recording connector observes its default `true`.

- [ ] **Step 4: Pass the non-selecting flag from the materializer**

Change the schedule call in `materializeMember` to:

```dart
_connector.scheduleMemberConnect(
  team,
  member,
  tab,
  selectMember: false,
);
```

- [ ] **Step 5: Run the focused test and verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/tab_member_materializer_test.dart --plain-name "materialize resolves numbered instance ids from session roster"`

Expected: PASS.

- [ ] **Step 6: Run the full materializer test file**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/tab_member_materializer_test.dart`

Expected: PASS with no test failures.

### Task 2: Prevent lazy terminal restore from reselecting its target

**Files:**
- Modify: `client/lib/cubits/chat/session_launch_service.dart:829-854`
- Test: `client/test/cubits/chat/cubit_lazy_spawn_test.dart`

**Interfaces:**
- Consumes: `SessionLaunchService.ensureMemberTerminalForView(sessionId, memberId)` and the existing `ChatTab.selectedMemberId` state.
- Produces: Lazy terminal restoration starts the requested shell without modifying the current selection; `selectMember` and explicit `openMemberTab` remain selecting operations.

- [ ] **Step 1: Add a failing lazy-restore regression test**

Add a test in `cubit_lazy_spawn_test.dart` that opens the existing mixed session, removes `worker-1`'s shell, sets the terminal view, leaves `team-lead` selected, and directly restores `worker-1`:

```dart
test(
  'lazy terminal restore starts a member without changing current selection',
  () async {
    final opened = await openMixedSessionWithShells(
      cubit: cubit,
      repo: repo,
      postFrame: postFrame,
    );
    final tab = cubit.activeTab!;
    tab.memberShells.remove('worker-1');
    tab.reclaimedMemberIds.add('worker-1');
    tab.workbenchView = SessionWorkbenchView.terminal;
    tab.selectedMemberId = 'team-lead';
    tab.persistedSession = (await repo.loadSessions()).firstWhere(
      (s) => s.sessionId == opened.sessionId,
    );

    await cubit.ensureMemberTerminalForView(opened.sessionId, 'worker-1');
    await drainPendingAsyncWork();

    expect(tab.selectedMemberId, 'team-lead');
    expect(tab.membersPendingConnect, contains('worker-1'));
  },
);
```

- [ ] **Step 2: Run the new test and verify it fails for the current behavior**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/cubit_lazy_spawn_test.dart --plain-name "lazy terminal restore starts a member without changing current selection"`

Expected: FAIL because `ensureMemberTerminalForView` reaches the scheduler with its default `selectMember: true`, changing the selection to `worker-1`.

- [ ] **Step 3: Pass the non-selecting flag from lazy restoration**

Change the final scheduler call in `ensureMemberTerminalForView` to:

```dart
_memberConnectScheduler.schedule(
  team,
  member,
  tab,
  selectMember: false,
);
```

- [ ] **Step 4: Run the focused lazy-spawn tests**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/cubit_lazy_spawn_test.dart`

Expected: PASS, including the existing tests that selecting a member or revealing Terminal still starts that member.

- [ ] **Step 5: Verify explicit opening still selects the requested member**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat_cubit_test.dart --plain-name "openMemberTab ignores duplicate taps while member connect is pending"`

Expected: PASS; this path remains explicit and continues to select the member requested by `openMemberTab`.

### Task 3: Cross-check and hand off

**Files:**
- Modify: none beyond Tasks 1–2.
- Test: `client/test/cubits/chat/tab_member_materializer_test.dart`, `client/test/cubits/chat/cubit_lazy_spawn_test.dart`, `client/test/cubits/chat_cubit_test.dart`

- [ ] **Step 1: Review the diff for scope and formatting**

Run: `git diff --check && git diff -- client/lib/cubits/chat/tab_member_materializer.dart client/lib/cubits/chat/session_launch_service.dart client/test/cubits/chat/tab_member_materializer_test.dart client/test/cubits/chat/cubit_lazy_spawn_test.dart`

Confirm only background/lazy selection intent and its tests changed; do not stage unrelated existing worktree modifications.

- [ ] **Step 2: Run Flutter analysis**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: exit code 0.

- [ ] **Step 3: Run the complete repository test suite through the required runner**

Run: `cd client && dart run tool/run_tests.dart`

Expected: exit code 0 with no failed tests.

- [ ] **Step 4: Report the changed files and verification evidence**

Include the two production call sites changed, the regression tests added, and the exact analysis/test results. Do not claim completion if either final command fails.
