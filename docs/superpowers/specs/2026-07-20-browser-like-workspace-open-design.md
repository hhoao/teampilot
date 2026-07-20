# Browser-like workspace open

## Problem

First open of a workspace still feels like a freeze: even after deferring the compose
`TextField`, the tab slot sync-mounts `WorkspacePage` + IDE + sidebar list in one or
two heavy frames. Users want browser-like feedback — tab and empty page chrome first,
then progressive content with skeletons.

## Goals

1. **Frame 0:** title-bar tab + empty `WorkspacePageCardShell` (no IdeShell / Editable).
2. **Frame 1+:** pane chrome with sidebar/center skeletons.
3. **Frame 2+:** real session list + landing body.
4. **Idle:** compose `TextField` (existing `awaitIdle`); no autofocus on open.

## Design

### Instant chrome

Move `TpDeferredForegroundMount` from inside `WorkspacePage` up to
`HomeWorkspaceBodyStack._WorkspaceTabSlot`, wrapping `BlocProvider` + `WorkspacePage`.
Placeholder is a full `WorkspacePageCardShell` so Frame 0 matches real chrome.
Remove the inner page-level defer to avoid double-defer.

### Skeletons

- Sidebar list body: wrap with `TpDeferredMountShell(delayFrames: 1)` and
  `_SessionListSkeleton` placeholder even when sessions are already hydrated.
- Landing: `TpDeferredMountShell(delayFrames: 2)` around `WorkspaceChatLanding` with a lightweight
  landing skeleton placeholder (header bars + compose card outline). Sidebar list stays at
  `delayFrames: 1` so list and landing do not share one mount frame.

### Compose fast path

When compose landing is active (no session workbench tab), build
`WorkspaceComposeLandingPane` without the full `ChatPageShell` workbench projection
chain so Stage-1 IDE mount does not pay run/editor/workbench watches.

## Non-goals

- Cheaper `RenderEditable` / custom editor
- Boot-time TextField warm-up
- Title-bar `AnimatedOpacity` cleanup
