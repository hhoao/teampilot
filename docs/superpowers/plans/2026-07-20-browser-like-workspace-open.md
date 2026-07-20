# Browser-like workspace open — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make first-open workspace feel like a browser: paint tab + empty card chrome immediately, then fill sidebar/center with skeletons and progressive mounts.

**Architecture:** Defer `WorkspacePage` at `_WorkspaceTabSlot` behind `DeferredForegroundMount` with `WorkspacePageCardShell` placeholder; wrap sidebar list and landing body in `DeferredMountShell` with skeletons; short-circuit compose landing before `ChatPageShell`.

**Tech Stack:** Flutter, flutter_bloc, existing `DeferredForegroundMount` / `DeferredMountShell` / `KeepAliveLayer`.

**Spec:** [2026-07-20-browser-like-workspace-open-design.md](../specs/2026-07-20-browser-like-workspace-open-design.md)

---

### Task 1: Instant chrome at tab slot

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_body_stack.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_page.dart`
- Test: `client/test/pages/home_workspace/workspace_tab_slot_defer_test.dart`

- [x] Wrap `BlocProvider` + `WorkspacePage` in `DeferredForegroundMount(retainWhenInactive: true)`
- [x] Placeholder = `WorkspacePageCardShell(chrome: workspace, …)`
- [x] Remove inner `DeferredForegroundMount` from `_buildLivePage`

### Task 2: Sidebar session-list skeleton defer

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart`

- [x] Wrap `_buildBody` in `DeferredMountShell(delayFrames: 1, placeholder: _SessionListSkeleton())`

### Task 3: Landing skeleton defer

**Files:**
- Create: `client/lib/pages/home_workspace/workspace/workspace_landing_skeleton.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_compose_landing_pane.dart`

- [x] Add lightweight landing skeleton (header bars + compose card outline)
- [x] Wrap `WorkspaceChatLanding` in `DeferredMountShell(delayFrames: 1, awaitIdle: false)`

### Task 4: Compose fast path

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart`

- [x] When `composeLanding`, center = `WorkspaceComposeLandingPane` (skip `ChatPage` / `ChatPageShell`)

### Task 5: Tests

**Files:**
- Create/extend widget tests for defer structure
- Keep `open_workspace_nav_first_test.dart`

- [x] Tab slot shows card placeholder before page child
- [x] Sidebar / landing assert `DeferredMountShell` presence
- [x] Manual: DevTools open recording (Frame0 without IdeShell) — run after merge: open workspace, confirm Frame0 = tab + card chrome only

---
