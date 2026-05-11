# Session Tab Member Shells Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make chat workspace tabs represent sessions while member shells run behind the active session.

**Architecture:** Refactor `ChatCubit` so visible tabs are session tabs and background `TerminalSession` objects are stored per session/member. Keep `TerminalSession` launch behavior intact, and preserve the current center terminal view by displaying the selected member shell for the active session.

**Tech Stack:** Flutter, flutter_bloc, xterm, flutter_pty, flutter_test.

---

## File Structure

- Modify `client/lib/cubits/chat_cubit.dart`: change tab ownership from one terminal per tab to one session tab with member shells, add injectable terminal/session scheduling hooks for tests.
- Modify `client/lib/pages/chat_workbench.dart`: ensure the initial local session tab exists after the first frame and route toolbar actions through the active session/member shell.
- Modify `client/lib/widgets/context_sidebar.dart`: session tile clicks should open the selected persisted session tab, not force-open `team-lead` as a member tab.
- Modify `client/test/widget_test.dart`: update `ChatCubit` tests for session tabs and add a fake terminal session.

## Task 1: Cubit Session Tabs

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart`
- Test: `client/test/widget_test.dart`

- [ ] Write a failing test named `chat cubit opens member shells inside one session tab` that creates a `ChatCubit` with a fake `TerminalSession` factory and immediate scheduler, calls `openMemberTab` for `team-lead` and `developer`, and expects `state.tabs.length == 1`, `state.tabs.single.id == 'local-test-team'`, `selectedMemberId == 'dev'`, and both members running.
- [ ] Run `cd client && flutter test test/widget_test.dart --plain-name "chat cubit opens member shells inside one session tab"` and confirm it fails because each member still creates a tab.
- [ ] Refactor `ChatCubit` so `_InternalTab` owns `resumeSession` plus `memberShells`, add `ensureSessionTab`, change `openMemberTab` to create or reuse a local session tab and start the member shell without adding a member tab.
- [ ] Run the focused test again and confirm it passes.

## Task 2: Session Selection Preservation

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart`
- Test: `client/test/widget_test.dart`

- [ ] Write a failing test named `chat cubit keeps persisted session tabs separate from member selection` that opens a `FlashskySession`, opens two members, and expects the visible tab id to remain the session id while selected member changes.
- [ ] Run the focused test and confirm it fails before the final routing changes.
- [ ] Update `selectTab`, `closeTab`, `isMemberRunning`, `connectSession`, `disconnectSession`, and `restartSession` to operate on the active session tab's selected member shell.
- [ ] Run the focused test and confirm it passes.

## Task 3: UI Routing

**Files:**
- Modify: `client/lib/pages/chat_workbench.dart`
- Modify: `client/lib/widgets/context_sidebar.dart`
- Test: `client/test/widget_test.dart`

- [ ] Update the widget smoke test to expect the default local session tab title and verify tapping a member row does not add a second top-level tab.
- [ ] Run the widget smoke test and confirm it fails before UI routing is complete.
- [ ] In `ChatWorkbench`, schedule `ensureSessionTab(team)` after the first frame, and read `currentSession` for the active selected member shell.
- [ ] In `ContextSidebar`, call `openSessionTab(session)` when a session tile is tapped and stop opening `team-lead` as a member tab automatically.
- [ ] Run the widget smoke test and confirm it passes.

## Task 4: Verification

**Files:**
- Verify only.

- [ ] Run `cd client && flutter test`.
- [ ] Run `cd client && flutter analyze`.
- [ ] If either command fails, fix the failure with the smallest scoped change and rerun the failed command.
