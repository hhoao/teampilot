# Remove Chat Page Team Actions Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the chat page's top single-member/team action row while preserving the Chat/Terminal switch and all underlying launch capabilities.

**Architecture:** Keep the generic `WorkspaceShellActionsBar` and `ChatCubit` APIs intact. Remove only the chat-specific action construction and mounting from `ChatPageShell`; the existing session workbench toggle path in `chat_workbench.dart` remains untouched.

**Tech Stack:** Flutter, Dart, flutter_bloc, flutter_test, repository test wrapper.

## Global Constraints

- Never invoke `flutter test` directly; use `cd client && dart run tool/run_tests.dart <path/options>`.
- Before completion run `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Preserve unrelated working-tree modifications.
- Do not use `Directory.current` or add storage dependencies.

---

### Task 1: Add a failing regression assertion for the removed action row

**Files:**
- Modify: `client/test/pages/chat/chat_page_shell_narrow_test.dart`

**Interfaces:**
- Consumes the existing `_NarrowHarness`, `ChatPageShell`, `LaunchProfileState`, `TeamProfile`, and `AppKeys` test seams.
- Produces a focused widget assertion that a team session renders neither `AppKeys.openTeamLeadButton` nor `AppKeys.openTeamButton`.

- [ ] **Step 1: Write the failing test**

Import `package:teampilot/models/team_config.dart` for `TeamProfile` and use the already exported `LaunchProfileState` from `launch_profile_cubit.dart`. Add a team-session widget test after the existing viewport tests. Seed the launch-profile cubit with a minimal `TeamProfile`, register an `AppSession` whose `sessionTeam` is that profile's id, pump the harness at `_wideSize`, and assert both action keys are absent:

```dart
testWidgets('team session omits the top member and team action row',
    (tester) async {
  final harness = await _setUpHarness(tester);
  final team = TeamProfile(id: 'team-1', name: 'Team 1');
  harness._teamCubit.emit(
    LaunchProfileState(
      identities: [team],
      isLoading: false,
    ),
  );
  final session = _session('sess-team', 'Team session').copyWith(
    sessionTeam: team.id,
  );
  _registerSession(
    harness.chatCubit,
    harness.workbenchCubit,
    session,
    'Team session',
  );

  await harness.pump(tester, _wideSize);

  expect(find.byKey(AppKeys.openTeamLeadButton), findsNothing);
  expect(find.byKey(AppKeys.openTeamButton), findsNothing);
});
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
cd client && dart run tool/run_tests.dart test/pages/chat/chat_page_shell_narrow_test.dart --plain-name="team session omits the top member and team action row"
```

Expected: FAIL because the current chat shell still mounts the two keyed buttons for a team session.

### Task 2: Remove only the chat-specific top action row

**Files:**
- Modify: `client/lib/pages/chat/chat_page_shell.dart:115-275`
- Test: `client/test/pages/chat/chat_page_shell_narrow_test.dart`

**Interfaces:**
- Consumes the existing workbench group layout and generic `WorkspaceShellActionsBar`.
- Produces a chat shell with no `_chatActions` row while leaving `SessionWorkbenchViewIcons` / `SessionWorkbenchViewToggle` and `ChatCubit` launch methods unchanged.

- [ ] **Step 1: Remove chat action construction and mounting**

In `_ChatWorkspaceShell.build`, remove the `WorkspaceActiveContext` lookup used only for these actions, the `singleGroup`/`chatActions` variables, the conditional `Column` that mounts `WorkspaceShellActionsBar`, and the `actions: ...` argument passed to `WorkbenchGroupHost`. Keep the `WorkbenchTabDragHost` wrapping the split view. Delete `_chatActions` and its button callbacks, but do not edit `WorkspaceShellActionsBar`, `ChatCubit.openMemberTab`, or `ChatCubit.launchAllMembers`.

The resulting return shape should remain equivalent to:

```dart
return WorkbenchTabDragHost(child: splitView);
```

and each `WorkbenchGroupHost` should no longer receive chat action widgets.

- [ ] **Step 2: Run the focused regression test and existing toggle test**

Run:

```bash
cd client && dart run tool/run_tests.dart test/pages/chat/chat_page_shell_narrow_test.dart test/pages/chat/session_workbench_view_toggle_test.dart
```

Expected: PASS, including the new absence assertion and the existing Chat/Terminal rendering and switching tests.

- [ ] **Step 3: Run static analysis**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no errors or warnings introduced by the removed imports/locals.

- [ ] **Step 4: Review the diff and commit implementation**

Run:

```bash
git diff --check
git diff -- client/lib/pages/chat/chat_page_shell.dart client/test/pages/chat/chat_page_shell_narrow_test.dart
git status --short
```

Confirm only the intended production/test files are changed, then commit:

```bash
git add client/lib/pages/chat/chat_page_shell.dart client/test/pages/chat/chat_page_shell_narrow_test.dart
git commit -m "fix(chat): remove team action bar"
```

### Task 3: Full verification

**Files:**
- No additional files.

- [ ] **Step 1: Run the required full test suite**

Run:

```bash
cd client && dart run tool/run_tests.dart
```

Expected: the repository test suite completes successfully.

- [ ] **Step 2: Re-run final analysis if needed and report evidence**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: clean analysis. Report the focused tests, full suite, and analyzer results without claiming success if any command fails.
