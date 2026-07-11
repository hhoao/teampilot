# Workspace Panes IDE Shell design

**Date:** 2026-07-10  
**Status:** Approved (spec review)  
**Related:** [panes](https://github.com/SoFluffyOS/panes) (`panes` on pub.dev), `ResizableSplitView`, `RightToolsHost`, `WorkspaceShellCenterColumnWithTerminal`, `LayoutCubit` / `LayoutPreferences`, [Workbench Center Tabs](2026-07-10-workbench-center-tabs-design.md)

## Summary

Replace the workspace page’s nested custom splits with a single **app-owned IDE shell** (`WorkspaceIdeShell`) that uses the [panes](https://github.com/SoFluffyOS/panes) package for resizable multi-pane interaction and a medium Islands-style visual (gutter + rounded panels), while keeping **TeamPilot product chrome** (center workbench tabs, right-tools content, terminal chrome) unchanged.

`LayoutCubit` / `LayoutPreferences` remain the sole persistence and intent source of truth. panes is a view/interaction engine only. The bottom workspace terminal becomes **full-bleed** under left + center + right. Narrow layouts use the **same pane model** plus a breakpoint policy (overlay for side panes), not a permanent drawer fork.

## Goals

| Goal | Description |
|------|-------------|
| Unified IDE geometry | One shell owns left / center / right / bottom splits |
| Full-bleed bottom | Workspace terminal spans under sidebar + workbench + right tools |
| App-owned state | Prefs + policy drive visibility/sizes; panes does not own persistence |
| Islands (medium) | Gutter + rounded floating panels; keep existing tab/tool chrome |
| Narrow = policy | One model; breakpoint collapses sides and opens overlays |
| Stable terminal subtree | Toggling sides must not reparent/dispose center or bottom PTY hosts |
| Swappable engine | Shell + policy APIs survive if panes fails spike (fallback to custom splits) |

## Non-goals

- Replacing `WorkbenchCubit` / `WorkspaceShell` tabs with panes `TabbedPane`
- Using panes `save()` / `load()` as layout source of truth
- Per-workspace layout persistence (may add later without changing shell API)
- Migrating non-workspace splits (e.g. LLM config) in this change
- Redesigning right-tools or terminal **internal** UI
- Heavy Fleet example chrome / copying panes example colors wholesale

## Problem with the current architecture

Today the workspace workbench is three nested concerns:

1. `WorkspaceSplitPane` — horizontal `ResizableSplitView` (sidebar | main)
2. `RightToolsHost` — horizontal split (center | right tools) with reveal animation and careful non-reparenting
3. `WorkspaceShellCenterColumnWithTerminal` — vertical split (workbench | bottom terminal) **only under center**, not under right tools

Plus a separate narrow path (`_ChatPageDrawerLayout`) for right tools.

This works, but:

- Resizer UX, maximize, and Islands visuals would be reimplemented ad hoc
- Bottom-under-center-only blocks a standard IDE layout
- Dual wide/narrow shells make every layout feature a two-path change
- Layout intent is already in `LayoutCubit`, but geometry wiring is scattered across hosts

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Approach | App-owned `WorkspaceIdeShell` wrapping panes (`IdeLayout` / `MultiPane`) |
| Bottom span | Left + center + right (VS Code / Fleet style) |
| Islands | Medium: gutter + rounded panels; TeamPilot chrome kept |
| Narrow | Same pane model + `WorkspacePanePolicy`; overlays replace drawer long-term |
| Persistence | `LayoutCubit` only; panes controller is derived |
| Center tabs | Unchanged; no panes `TabbedPane` |
| Dependency | `panes: ^1.3.0` (pin); vendor only if patching |
| Sequencing | Do not mix with WorkbenchCubit semantic changes; prefer after center-tabs stability |

## Canonical primitives

| Primitive | Owner | Role |
|-----------|--------|------|
| **Layout intent** | `LayoutPreferences` via `LayoutCubit` | User-facing visibility + sizes (+ new `sidebarVisible`) |
| **Effective layout** | `WorkspacePanePolicy` | Pure function: prefs + viewport + route context → what is shown / overlay vs docked |
| **IDE shell** | `WorkspaceIdeShell` | Owns `IdeController` lifecycle; syncs policy ↔ panes; PTY drag hold; Islands chrome |
| **Center chrome** | `WorkspaceShell` + `WorkbenchCubit` | Session / file / diff tabs and body |
| **Side / bottom content** | Existing panels | `WorkspaceSidebar`, `RightToolsPanel`, `WorkspaceTerminalPanel` |

## Architecture

```
WorkspacePage
  └── WorkspaceIdeShell
        ├── reads LayoutCubit
        ├── WorkspacePanePolicy.effective(...)
        ├── IdeLayout / MultiPane + PaneTheme
        │     left   → WorkspaceSidebar
        │     center → ChatPage center column (WorkspaceShell + workbench body)
        │     right  → RightToolsPanel
        │     bottom → WorkspaceTerminalPanel (full-bleed)
        └── narrow: PaneOverlayHost for left/right by pane id
```

### Responsibility split

| Layer | Does | Does not |
|-------|------|----------|
| `LayoutCubit` | Persist intent; expose setters | Call panes APIs |
| `WorkspacePanePolicy` | Breakpoints, route-context hooks (v1: compose≡session), preset mapping | Widgets / I/O |
| `WorkspaceIdeShell` | Adapter, overlays, PTY hold, Islands wrapper | Own session/file/diff tabs |
| panes | Split interaction, maximize, resizer a11y | Persist app layout; host product tabs |

### Prefs ↔ pane mapping

| Prefs field | Pane |
|-------------|------|
| `sidebarWidth` | left size |
| `sidebarVisible` (**new**, default `true`) | left intent |
| `rightToolsWidth` / `rightToolsVisible` | right |
| `workspaceTerminalHeight` / `workspaceTerminalVisible` | bottom |
| (none) | center consumes remaining space |

Maximize state is **ephemeral UI** (not persisted).

`LayoutPreset` (`workbench` / `chatFocus` / `inspector`) maps through policy as an extension point; initial ship may only honor `workbench` behavior explicitly.

### Write-back rules

- **Size drag (locked):** while dragging, update local/controller geometry only; on **drag end**, commit once via `LayoutCubit.set*`. Do not debounce mid-drag cubit writes (avoids rebuild oscillation and matches PTY hold/flush).
- Visibility toggles → immediate intent write
- Breakpoint-forced collapse → **effective only**; must not overwrite user intent fields
- Drag start/end → existing `TerminalLayoutCoordinator` hold/flush

### Compose landing vs session (policy defaults)

Aligned with [Workbench Center Tabs](2026-07-10-workbench-center-tabs-design.md): compose is a **center body** state. Right tools on landing follow [Landing Default-Hide Right Tools](2026-07-11-landing-hide-right-tools-design.md): **default hidden** (effective-only); temporary override without persisting intent; file tree / git remain reachable after temporary reveal to open center tabs.

| Context | Effective left / right / bottom (wide) | Notes |
|---------|----------------------------------------|--------|
| **Session workbench** | Honor user intent | — |
| **Compose landing** | Left / bottom: honor user intent; **right: hidden by default** | Temporary override via `landingRightToolsOverride`; does not write `rightToolsVisible`. No compose-only geometry fork. |

Narrow: left/bottom breakpoint policy unchanged (collapse sides to overlay; bottom still follows intent when width allows). Right pane on landing follows the same effective-right rule as wide dock (default hide + temporary override). See [Landing Default-Hide Right Tools](2026-07-11-landing-hide-right-tools-design.md) for toggle/dismiss routing and override clearing.

### Narrow breakpoint

Replace today’s `Platform.isAndroid` / `useRightToolsAsDrawer` fork with a **viewport width** threshold owned by `WorkspacePanePolicy` (single constant). Initial value: pick during spike (candidate ~800–900 logical px); document the chosen constant in code. Android phones fall under narrow via width, not a separate platform shell.

**Overlay vs intent (locked):** on narrow, `*Visible` intent means “user wants this pane available,” not “docked.” Effective docked visibility for left/right is false below the breakpoint; opening the pane shows an **overlay** keyed by pane id. Closing the overlay sets intent to hidden only if the user explicitly dismisses it (same as today’s drawer dismiss → hide). Wide layouts map intent directly to docked visibility.

### Lifecycle constraints

1. Toggling left/right must not dispose or reparent center/bottom PTY hosts. Spike panes hide behavior; if hide disposes children, shell keeps children mounted (e.g. visibility/offstage strategy) while syncing controller.
2. Bottom panel key stays workspace-scoped (`workspace-terminal-$workspaceId`), not cwd.
3. One `IdeController` per `WorkspaceIdeShell` `State` (per open title-bar workspace). Layout prefs remain **app-global** (same as today).
4. Pages must not touch `IdeController` directly.

### `ChatPage` thinning

`ChatPage` / `ChatPageShell` become the **center builder content** only. Geometry hosts move up:

**Remove from workspace path (after cutover):** `RightToolsHost`, `WorkspaceShellCenterColumnWithTerminal`, nested sidebar split inside `WorkspaceSplitPane`, long-term `_ChatPageDrawerLayout`.

`WorkspaceSplitPane` becomes bind worktree/tools-scope + mount `WorkspaceIdeShell`.

## Visual (Islands medium)

- `PaneTheme` for resizer colors/thickness aligned to app `ColorScheme`
- Shared gutter (≈6–8px) and rounded pane chrome wrapper around each region
- Do **not** replace `WorkspaceShell` tab row, right-tools tool strip, or terminal tab bar styling with panes `TabbedPane` look
- Full-bleed bottom participates in the same gutter system

## Error handling / fallback

| Case | Response |
|------|----------|
| Spike: panes cannot full-bleed bottom, or hide disposes PTY subtrees unacceptably | Keep `WorkspaceIdeShell` + `WorkspacePanePolicy` APIs; swap engine to custom `ResizableSplitView` composition |
| Sync oscillation during drag | Prevented by drag-end-only cubit commit (see write-back rules) |
| Missing new prefs keys | `sidebarVisible` defaults `true`; sizes clamp with existing min/max constants |
| Narrow overlay / missing cwd | Same empty states as today; no crash |

## Testing

1. **`WorkspacePanePolicy` unit tests** — wide/narrow, intent vs effective, compose≡session visibility in v1, preset hooks
2. **Adapter unit tests** — prefs → controller sync; breakpoint does not mutate intent
3. **Widget smoke** — four builders mount; toggling right does not change bottom terminal `ValueKey` / center identity signals used for PTY stability
4. Do not unit-test panes’ internal layout math

## Migration slices

1. **Spike** — minimal `IdeLayout`: full-bleed bottom, hide/dispose behavior, drag-end size commit + PTY hold. Fail → custom `ResizableSplitView` engine behind the same shell API. Also choose the narrow width breakpoint constant.
2. **Policy + `sidebarVisible`** in prefs (no big UI swap yet). Wire **`sidebarWidth` write-back** through `LayoutCubit` (today `WorkspaceSplitPane` keeps width in local state only — prefs field exists but is not the live source).
3. **Desktop wide: `WorkspaceIdeShell` cutover**; short transitional narrow path allowed only briefly. Accept panes native show/hide for side panes (no requirement to preserve `RightToolsHost`’s ~200ms width reveal animation unless a cheap equivalent falls out of panes theming).
4. **Narrow overlays**; delete drawer / `Platform.isAndroid` special-case
5. **Islands chrome**; delete dead hosts (`RightToolsHost`, etc.)
6. No `WorkbenchCubit` semantic changes in these slices

## Relationship to workbench center tabs

This design **composes under** the center-tabs work: tabs live inside the center pane. Implementation should not rewrite tab identity/order/active selection. Prefer landing after center-tabs is stable, or strict PR boundaries if parallel.

## Success criteria

- Workspace page uses one IDE shell for geometry on desktop wide layout
- Bottom terminal spans full width under left + center + right
- Toggling right tools does not tear down workspace terminal / agent PTY state
- Layout sizes/visibility still round-trip through `LayoutPreferences`
- Narrow path shares policy model (overlay), not a forever-dual shell
- Center tab behavior unchanged relative to the workbench-center-tabs design
