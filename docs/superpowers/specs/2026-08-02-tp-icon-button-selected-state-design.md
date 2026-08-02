# TpIconButton selected state + mobile hamburger active chrome

**Date:** 2026-08-02  
**Status:** approved for planning  
**Scope:** Add `selected` to `TpIconButton` in `shared_ui`; wire mobile title-bar drawer hamburger (home + workspace) and desktop sidebar visibility toggle to pill-matched active chrome.  
**Owner constraints:** match `_HomePill` active colors; hamburger open icon = `Icons.menu_open`; do not touch right-tools visibility toggle.

## Problem

1. Mobile title-bar hamburger uses a plain `TpIconButton` with no open-state affordance, so users cannot tell whether the drawer/sidebar overlay is open.
2. Desktop `WorkspaceShellSidebarVisibilityToggle` only tints the icon `primary` when open — weaker and inconsistent with the home-pill active treatment beside the hamburger.
3. Active fill/border values live only on `_HomePill`; toolbar icon buttons have no shared selected chrome.

## Goals

1. Give `TpIconButton` a first-class `selected` flag that applies `_HomePill`-matched active chrome.
2. When the mobile drawer/sidebar is open, the hamburger shows `selected` chrome and swaps `Icons.menu` → `Icons.menu_open`.
3. Desktop left-sidebar visibility toggle uses the same `selected` chrome (icon remains `Icons.view_sidebar_outlined`).
4. Cover home (`TpSidebarTrigger` / `openMobile`) and workspace (`mobileWorkspaceDrawerOpen`) paths in `_HomeTitleBarMobileDrawerTrigger`.

## Non-goals

- Changing `WorkspaceShellRightToolsVisibilityToggle`.
- Animated icon morph between `menu` and `menu_open`.
- Extracting `_HomePill` into a shared selectable surface widget.
- Expanding `selected` to every toolbar icon that currently hand-tints `color: cs.primary`.

## Decisions (locked)

| Topic | Decision |
|-------|----------|
| Visual when `selected` | Background `primary` @ **0.16**; border `primary` @ **0.28**; icon `primary` — same alphas as `_HomePill` |
| Border radius | Keep `TpIconButton` default (`kDefaultBorderRadius` = 6); do not force pill’s 8 |
| Override precedence | Explicit `color` / `backgroundColor` still win over `selected` defaults |
| Hamburger closed icon | `Icons.menu` |
| Hamburger open icon | `Icons.menu_open` |
| Desktop sidebar toggle icon | Stay `Icons.view_sidebar_outlined`; only set `selected: effectiveOpen` |
| Home open signal | `TpSidebarScope.openMobile` |
| Workspace open signal | `mobileWorkspaceDrawerOpen(layoutState:, composeLanding:)` |
| Approach | Extend `TpIconButton` in place (no new widget) |
| Right tools toggle | Out of scope |

## Architecture

```
TpIconButton(selected)
  └─ selected chrome (bg / border / icon color)

TpSidebarTrigger(selected, icon…)
  └─ home title-bar path (openMobile)

_HomeTitleBarMobileDrawerTrigger
  ├─ activeTabKey == null → TpSidebarTrigger(selected: openMobile, menu/menu_open)
  └─ else → TpIconButton(selected: mobileWorkspaceDrawerOpen, menu/menu_open)

WorkspaceShellSidebarVisibilityToggle
  └─ TpIconButton(selected: effectiveOpen, view_sidebar_outlined)
```

## Behavior

| Surface | Open | Closed |
|---------|------|--------|
| Mobile hamburger | `selected` + `menu_open` | not selected + `menu` |
| Desktop sidebar toggle | `selected` + same icon | not selected + same icon |

Tap behavior unchanged: toggle open/close as today.

## Testing

1. **shared_ui:** `TpIconButton(selected: true)` resolves primary fill/border/icon (and respects explicit `color` / `backgroundColor` overrides).
2. **Title bar:** mobile workspace + home paths — when drawer/sidebar open, find `menu_open` and `selected: true` on the trigger `TpIconButton`.
3. **Sidebar toggle:** update `workspace_shell_sidebar_toggle_test` to assert `selected` instead of (or in addition to) hand-set `color`.

## Implementation notes

- `TpIconButton` `BoxDecoration` must paint `border` when selected (today only `color: backgroundColor`).
- `_HomeTitleBarMobileDrawerTrigger` workspace path needs rebuild on layout/chat changes (`BlocBuilder` on `LayoutCubit` + compose-landing from `ChatCubit`) so `selected`/icon stay in sync.
- `TpSidebarTrigger` should accept optional `selected` and optional icon override (or choose icon from `selected`) so home path stays one widget.
