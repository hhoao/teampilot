# Workspace Search Isolation Design

## Problem

When multiple workspace tabs are open, a search initiated from workspace A can
include a session belonging to workspace B. Searches can also cancel one
another when two workspace search panels receive input close together.

## Root cause

`workspace.sessionIds` is an ordering projection, but
`sessionsForWorkspace()` currently treats every ID in that projection as if
the resolved `AppSession` belonged to the workspace. A stale or mismatched ID
therefore crosses the workspace boundary.

`WorkspaceSearchPanel` uses one process-wide debounce key for every panel.
Because `Debounces` stores operations by key, typing in one workspace replaces
the pending operation in another workspace.

## Design

1. Define the workspace/session join by `AppSession.workspaceId`. Use
   `workspace.sessionIds` only to order sessions already owned by that
   workspace, then append owned sessions that are absent from the projection.
2. Rebuild the hydrated workspace's `sessionIds` in
   `SessionDataStore.mergeWorkspaceSessions()` from the sessions actually
   loaded for that workspace. This repairs the projection at the state
   hydration boundary instead of carrying stale associations forward.
3. Give each `WorkspaceSearchPanel` a dedicated `Debouncer` instance and
   dispose it with the panel. Debounce state is owned by the panel that uses
   it, so workspace tabs cannot cancel each other.

## Non-goals

- Do not add broad fallback filtering at individual search call sites.
- Do not change global search index ownership or filesystem root semantics;
  those are already keyed by workspace/root.
- Do not touch unrelated dirty-worktree changes.

## Verification

- Add a regression test proving a mismatched session ID is excluded.
- Add a regression test proving two debouncer instances execute independently.
- Run the focused tests, then Flutter analyze and the repository test runner.
