# Workspace Chrome Active Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make workspace pane controls use the route-selected workspace rather than a non-reactive Chat runtime mirror.

**Architecture:** `HomeTitleBar.activeTabKey` is the route-owned active workspace key. Thread it into desktop pane controls and the mobile drawer trigger, then use it for the Workbench landing-state lookup. This leaves Chat runtime registration and layout persistence untouched.

**Tech Stack:** Flutter, flutter_bloc, flutter_test.

## Global Constraints

- Do not make `ChatCubit` emit merely to refresh title-bar chrome.
- Do not change persisted layout preference semantics.
- Cover the stale Chat tab-store scenario with a real widget interaction.

---

### Task 1: Prove the explicit workspace key controls landing behavior

**Files:**
- Create: `client/test/pages/workspace_shell/workspace_shell_tabs_test.dart`
- Modify: none

**Interfaces:**
- Consumes: `WorkspaceShellRightToolsVisibilityToggle(workspaceId: String)`.
- Produces: regression coverage for a landing workspace whose Chat tab-store id is stale.

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('right-tools toggle uses its explicit workspace while chat scope is stale', (tester) async {
  workbench.enterLanding('landing-workspace');
  chat.setActiveWorkspace('previous-workspace');
  await tester.pumpWidget(/* providers + toggle workspaceId: 'landing-workspace' */);

  await tester.tap(find.byKey(AppKeys.rightToolsVisibilityButton));
  await tester.pump();

  expect(layout.state.landingRightToolsOverride, isTrue);
  expect(layout.state.preferences.rightToolsVisible, isTrue);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/pages/workspace_shell/workspace_shell_tabs_test.dart`

Expected: compilation fails because the toggle does not yet accept an explicit workspace key.

- [ ] **Step 3: Implement the minimal code**

Add a required `workspaceId` to `WorkspaceShellPaneVisibilityToggles` and `WorkspaceShellRightToolsVisibilityToggle`; use it in the `WorkbenchCubit` selector. Pass `HomeTitleBar.activeTabKey!` from the desktop title bar.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/pages/workspace_shell/workspace_shell_tabs_test.dart`

Expected: PASS.

### Task 2: Apply the same canonical key to mobile chrome

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_title_bar.dart`
- Test: `client/test/pages/home_workspace/home_workspace_title_bar_test.dart`

**Interfaces:**
- Consumes: `_HomeTitleBarMobileDrawerTrigger(activeWorkspaceId: String?)`.
- Produces: mobile drawer compose-awareness based on the active route key.

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('mobile drawer uses active workspace key when chat scope is stale', (tester) async {
  workbench.enterLanding('ws-a');
  chat.setActiveWorkspace('ws-b');
  await tester.pumpWidget(/* HomeTitleBar activeTabKey: 'ws-a' */);
  await tester.tap(find.byIcon(Icons.menu));
  expect(layout.state.landingRightToolsOverride, isTrue);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/pages/home_workspace/home_workspace_title_bar_test.dart`

Expected: the drawer uses the stale Chat workspace and does not set the landing override.

- [ ] **Step 3: Implement the minimal code**

Pass `activeTabKey` into `_HomeTitleBarMobileDrawerTrigger` and select Workbench state using that key, not `ChatCubit.tabStore.activeWorkspaceId`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/pages/home_workspace/home_workspace_title_bar_test.dart`

Expected: PASS.

### Task 3: Verify the focused change

**Files:**
- Modify: none

- [ ] **Step 1: Format modified Dart files**

Run: `cd client && dart format lib/pages/workspace_shell/workspace_shell_tabs.dart lib/pages/home_workspace/home_workspace_title_bar.dart test/pages/workspace_shell/workspace_shell_tabs_test.dart test/pages/home_workspace/home_workspace_title_bar_test.dart`

- [ ] **Step 2: Run focused tests**

Run: `cd client && flutter test test/pages/workspace_shell/workspace_shell_tabs_test.dart test/pages/home_workspace/home_workspace_title_bar_test.dart`

Expected: PASS.

- [ ] **Step 3: Run static analysis**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: exit code 0.
