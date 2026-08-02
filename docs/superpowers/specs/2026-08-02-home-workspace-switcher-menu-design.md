# Home workspace switcher menu (title-bar ⋯)

**Date:** 2026-08-02  
**Status:** approved design  
**Scope:** title-bar overflow menu formerly “recently closed” only — mobile tap + open tabs + create

## Problem

The title-bar `⋯` menu lists only recently closed workspaces and opens on hover with `onTap: null`, so it is unusable on mobile. Mobile users need a tappable entry point to create a workspace, jump to an already-open tab, or reopen a recently closed one.

## Goals

- Same menu **content** on desktop and mobile.
- **Desktop:** hover still opens the menu; click on the anchor also toggles it.
- **Mobile:** click/tap on the anchor opens/closes the menu.
- Menu sections (top → bottom):
  1. **Create workspace** — one action row; reuses existing `showHomeNewWorkspaceDialog` and `newWorkspace` copy.
  2. **Open tabs** — current title-bar open workspace tabs; tap selects that tab (`onSelectTab`); active tab marked (check / highlight).
  3. **Recently closed** — existing `recentlyClosed` list (already excludes open tab keys in `HomeShell`); tap reopens via existing reopen path; empty state keeps `homeWorkspaceRecentlyClosedEmpty`.
- “Recent” means **recently closed** only (not `HomeRecentWorkspacesStore` visits).

## Non-goals

- Separate mobile BottomSheet presentation (same popover chrome as desktop).
- Closing open tabs from inside the menu.
- Showing “recent visits” / favorites in this menu.
- Changing title-bar tab strip layout beyond wiring the new menu widget.

## Approach

Extract `HomeWorkspaceSwitcherMenu` into `client/lib/pages/home_workspace/home_workspace_switcher_menu.dart` (replace private `_RecentlyClosedOverflowButton` in `home_workspace_title_bar.dart`).

Reuse `TpActionMenuAnchor` + `TpPopoverController`. Anchor is `TpIconButton` (`Icons.more_horiz`) with:

- `onTap` → toggle show/hide
- Desktop `MouseRegion` hover-open + delayed close (preserve current behavior)

### Inputs / callbacks

| Input | Role |
|-------|------|
| `openTabs` | `List<HomeWorkspaceTab>` (or equivalent id/name/topology) already built for the title bar |
| `activeTabKey` | Current active tab key; used for active mark |
| `recentlyClosed` | `List<HomeClosedWorkspaceEntry>` |
| `workspaces` | Live `Workspace` list for topology / path subtitle on closed entries |
| `launchProfiles` | Passed through for any existing subtitle helpers that need identities |
| `onCreate` | `VoidCallback` — host closes menu then calls `showHomeNewWorkspaceDialog` |
| `onSelectOpen` | `ValueChanged<String>` — tab key; same as title-bar tab select |
| `onReopenClosed` | `ValueChanged<String>` — tab key; existing reopen |

The menu must **not** read Cubits directly; create/select/reopen stay injected.

### Empty sections

- **Open tabs empty:** omit the “Open” section entirely (no empty placeholder).
- **Recently closed empty:** keep disabled empty row under the section header.
- Both empty: Create + Recently closed empty state.

### Close / create timing

- Choosing any menu item closes the popover.
- Create: hide menu first, then invoke `onCreate`, so the dialog is not stacked under an open popover. Existing dialog already navigates to the new workspace on success.

### l10n

- Reuse: `newWorkspace`, `homeWorkspaceRecentlyClosed`, `homeWorkspaceRecentlyClosedEmpty`.
- Add: `homeWorkspaceOpenTabs` (en: “Open”, zh: “已打开”) for the open-tabs section header.
- Tooltip on the anchor may stay `homeWorkspaceRecentlyClosed` or broaden later; default keep existing tooltip unless a follow-up renames the control.

## Wiring

- `HomeTitleBar` hosts `HomeWorkspaceSwitcherMenu` wherever `_RecentlyClosedOverflowButton` is today.
- `_HomeShellTitleBar` / `HomeShell` pass `openTabs`, `activeTabKey`, `onSelectTab`, and an `onCreate` that calls `showHomeNewWorkspaceDialog` with the usual repositories/cubit from context.

## Testing

- Unit/helpers: active marking; open section omitted when empty.
- Widget tests:
  - Tap anchor opens menu.
  - Menu shows Create; shows open items when provided; shows recently closed / empty state.
  - Tap open item → `onSelectOpen`; tap closed → `onReopenClosed`; tap create → `onCreate`.
  - Hover-open still works on desktop path (existing MouseRegion behavior).

## Out of scope follow-ups

- Rename control from “recently closed” mental model to “workspace switcher” in copy/tooltip.
- Keyboard / shortcut to open the menu.
