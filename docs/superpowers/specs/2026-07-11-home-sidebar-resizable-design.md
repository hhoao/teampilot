# Home Sidebar Resizable Width

**Date:** 2026-07-11  
**Status:** Approved  
**Owner decision:** Make the home (`/home-v2`) `HomeSidebar` drag-resizable via existing `TwoPaneSplitView` / `ResizableSplitView`, persist width in `LayoutPreferences`, enforce a right-pane minimum with no productized sidebar max.

## Problem

The Apifox-style home left rail (`HomeSidebar`) is hard-coded to `HomeSidebar.width = 420` inside a fixed `Row` in `HomePage`. Users cannot widen it for long team names or narrow it to give the right pane more room. The in-workspace conversation sidebar already supports resize + persistence via `LayoutCubit.sidebarWidth`; home does not.

## Goals

- Drag the home sidebar’s right edge to change its width.
- Persist the chosen width across app restarts (`LayoutCubit` / layout prefs JSON).
- Keep a usable sidebar minimum and a **right content minimum** so the detail pane cannot be crushed.
- Reuse the existing split-view interaction (divider, cursor, hit buffer) already used by settings hub / other two-pane shells.

## Non-goals

- Collapsing / hiding the home sidebar.
- Double-click-to-reset width.
- Changing the in-workspace `WorkspaceSidebar` resize behavior.
- Reusing `workspaceNavWidth` (settings hub nav; different default and limits).
- A productized hard maximum sidebar width (width is capped only by window size minus right-pane minimum).

## Decision

**`TwoPaneSplitView` on `HomePage` + new `homeSidebarWidth` preference.**

Mirror `WorkspaceSplitShell` / `WorkspaceHubDesktopShell`: primary pane = home sidebar, secondary = existing right content (with current padding). Width flows from `LayoutCubit`; drag updates call `setHomeSidebarWidth`.

## Behavior & constraints

| Constraint | Value | Notes |
|------------|-------|--------|
| Default width | `420` | Same as today’s `HomeSidebar.width` |
| Sidebar min | `~280` | Prevents crushing labels / identity drag gutter |
| Sidebar max | none (soft) | No dedicated max constant; `maxPrimarySize` set high enough that **`minSecondarySize` is the real cap** |
| Right pane min | `480` | Reuse `LayoutPreferences.minWorkspaceHubContentWidth` |

Narrow windows: rely on `ResizableSplitView` clamp (sidebar ≥ min, secondary ≥ min). No extra collapse or scroll shell.

Corrupt / missing prefs: missing, non-numeric, or out-of-range `homeSidebarWidth` → default `420`, then clamp to sidebar min. Never crash on bad JSON.

Persistence: same path as other layout widths (`LayoutCubit._save` on size change). No new debounce unless the shared path already has one.

## Architecture

### Layout wiring

`HomePage` today:

```text
Row(
  HomeSidebar(fixed width 420),
  Expanded(right pane + padding),
)
```

Becomes:

```text
TwoPaneSplitView(
  axis: horizontal,
  first: HomeSidebar (no fixed outer width),
  second: right pane + existing padding,
  initialSize: preferences.homeSidebarWidth,
  minSize: minHomeSidebarWidth,
  maxSize: large / unconstrained-by-product,
  minSecondarySize: minWorkspaceHubContentWidth (480),
  onSizeChanged: LayoutCubit.setHomeSidebarWidth,
)
```

`HomeSidebar` drops the outer `Container` fixed `width: HomeSidebar.width` so the split view owns width. Keep decoration (card fill, right border) and internal padding/content. Keep `HomeSidebar.width` as an alias of the default preference constant so call sites do not diverge.

### Persistence

| Piece | Change |
|-------|--------|
| `LayoutPreferences` | Add `homeSidebarWidth` (default 420; clamp ≥ min; no hard max) |
| JSON | Key `homeSidebarWidth`; absent → default |
| `LayoutCubit` | `setHomeSidebarWidth(double)` |
| `HomePage` | Read via `BlocBuilder` / `select`; write on drag |

Do **not** overload `sidebarWidth` (workspace conversation rail) or `workspaceNavWidth` (settings hub).

### Visual / interaction

Use `TwoPaneSplitView` / `ResizableSplitView` defaults for divider thickness and hit buffer so home matches settings hub feel. No custom drag handle chrome.

## Testing

- Unit: `LayoutPreferences` round-trip + clamp for `homeSidebarWidth` (missing key, below min, large values).
- Light widget/cubit coverage optional: size-changed callback reaches `setHomeSidebarWidth` (follow existing layout-pref test style if present).

## Out of scope follow-ups

- Home sidebar collapse / icon-only rail.
- Per-window or per-display width (single global preference is enough for v1).
