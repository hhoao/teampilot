# Source Control Auto-Refresh

**Date:** 2026-06-15
**Status:** approved

---

## 1. Problem

The source control panel (`GitSourceControlPanel`) only refreshes git status when the panel is first created, when cwd changes, when the user clicks the manual refresh button, or after a mutating git operation (stage/commit/discard). If an AI agent modifies files in a terminal, or the user edits files externally, the panel shows stale data until the user manually refreshes.

## 2. Design

Two changes, two files.

### 2.1 `GitSourceControlPanel` — `isActive` parameter + periodic timer

Give the panel an `isActive` boolean. When it transitions from `false` → `true` (user switched to the source control tab):

- Immediately call `GitCubit.refresh()` to get current git status
- Start a periodic timer (`Timer.periodic`, 15-second interval) that calls `refresh()`

When it transitions from `true` → `false` (user switched away):

- Cancel the timer

Existing behavior unchanged: manual refresh button still works; mutating ops still refresh on completion.

### 2.2 `RightToolsPanel` — compute and pass `isActive`

Change the views list from collection literal to imperative building so the git view's index is known. Compare against `WorkspaceToolsCubit.selectedIndexFor(projectId)` to determine if git is the active tab. Add `context.watch<WorkspaceToolsCubit>()` so the panel rebuilds when tab selection changes.

### 2.3 Refresh interval: 15 seconds

### 2.4 Safety

`GitCubit.refresh()` already guards against re-entrancy via `isLoading` checks and `isClosed` checks.

## 3. Affected files

| File | Change |
|------|--------|
| `client/lib/widgets/git/git_source_control_panel.dart` | Add `isActive` parameter, timer logic |
| `client/lib/widgets/right_tools/right_tools_panel.dart` | Compute active state, pass to git panel |

## 4. Behavior matrix

| Scenario | Before | After |
|----------|--------|-------|
| Switch to source control tab | Stale data | Immediate refresh + auto-refresh every 15 s |
| Stay on source control tab, agent modifies files | No update | Updates within 15 s |
| Switch to another tab | — | Timer stopped |
| Manual refresh / git ops | Works as before | Unchanged |
