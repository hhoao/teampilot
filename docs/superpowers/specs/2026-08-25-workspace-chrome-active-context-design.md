# Workspace Chrome Active Context Design

## Problem

The title-bar right-tools control derives its workspace from
`ChatTabStore.activeWorkspaceId`. That store is a runtime mirror and changing
it does not necessarily emit a `ChatCubit` state. The title bar can therefore
retain a prior workspace id while the route has already shown another
workspace's new-chat landing page. A click then changes persisted layout
preferences instead of the landing-only right-tools override.

## Decision

The home workspace route is the canonical owner of the active workspace for
workspace chrome. Pass `HomeTitleBar.activeTabKey` to its pane controls and
use that explicit key for the `WorkbenchCubit` lookup. Do the same for the
mobile drawer trigger. Neither control will read `ChatTabStore` to determine
whether the active page is a new-chat landing.

## Data flow

`HomeShell` derives `activeTabKey` from the current route and supplies it to
`HomeTitleBar`. `HomeTitleBar` passes the same value to the desktop pane
toggles or mobile drawer trigger. Those controls select
`WorkbenchCubit.state.bar(activeWorkspaceId).center.landingActive` and invoke
the compose-aware `LayoutCubit` operation. The active route rebuild always
updates this value, independently of ChatCubit emissions.

## Regression coverage

Add a widget test in the workspace-shell test area where the Chat tab-store
intentionally points at a different workspace from the explicitly supplied
workspace key. Mark only the explicit workspace as landing, tap the right
tools button, and assert that `landingRightToolsOverride` becomes true while
the persisted `rightToolsVisible` preference is unchanged.

## Scope

No persistence schema, `ChatCubit` emission behavior, or pane policy changes
are needed. This fixes both desktop title-bar and mobile drawer chrome by
removing their dependence on the stale runtime mirror.
