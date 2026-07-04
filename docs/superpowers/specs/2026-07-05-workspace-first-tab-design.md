# Workspace-first tab design

**Date:** 2026-07-05  
**Status:** Implemented

## Summary

One workspace maps to one title-bar tab (`tabKey == workspaceId`). Launch identity (personal preset / team) lives only on the compose landing and in the shared `WorkspaceLandingContextCubit`. Sidebar lists all sessions for the workspace without team filtering.

## Principles

- **No backward compatibility** — no `?as=` URLs, no composite tab keys, no identity launch dialog.
- **Session identity is authoritative** when opening existing sessions (`session.sessionTeam`, `profileId`, `cli`).
- **Landing / manage share** `WorkspaceLandingContextCubit` + `LandingPrefsStore`.
- **Right tools** follow `WorkspaceActiveContext`: active session team first, landing team roster preview when no session tab is open.

## Models

### `WorkspaceTabRef`

- Fields: `workspaceId` only.
- `tabKey` and route: `/home-v2/workspace/$workspaceId`.

### `LandingLaunchContext`

Compose + manage snapshot: `isPersonal`, `personalProfileId`, `presetId`, `teamId`.

### `WorkspaceActiveContext`

Resolved per workspace tab for chrome (right tools, chat shell):

| State | Members panel | Mailbox |
|-------|---------------|---------|
| Active team session | Session's team | Mixed team + TeamBus |
| Active personal session | Hidden | Hidden |
| Landing only, team mode | Landing team preview | Hidden |
| Landing simple mode | Hidden | Hidden |

## Routing

- Workspace: `/home-v2/workspace/:workspaceId`
- Manage: `?view=manage&section=…&profile=…`
- `/home-v2/workspace/:id/manage` redirects to canonical path and **preserves** `profile` and `section`.

## Opening workspaces

All entry points call `openWorkspace()` → `context.go('/home-v2/workspace/$id')` with no dialog.

## Manage panel

- `WorkspaceProfileIdentityBar` switches simple mode vs teams.
- Updates `WorkspaceLandingContextCubit` and URL `profile` query (bidirectional with landing chips).

## Chat scope

- `ChatTabStore` bucket key: `workspaceId`.
- Workspace tab activation does **not** apply `scopeSessionsToSelectedTeam` (home global view may still use that pref).
- Opening a sidebar session calls `selectTeam(session.sessionTeam)` before connect.

## Deleted legacy

- `home_launch_workspace_dialog.dart`
- `WorkspaceLaunchPrefsStore` (replaced by `LandingPrefsStore`)
- `openWorkspaceInNewTabWithIdentityPicker`, `?as=` parsing, `HomeWorkspaceTabKind`

## Tests

- `workspace_active_context_test.dart` — idle + landing profile id
- `workspace_launch_profile_route_test.dart` — `?profile=` deep links
- Updated title bar / tooltip tests for workspace-only tabs
