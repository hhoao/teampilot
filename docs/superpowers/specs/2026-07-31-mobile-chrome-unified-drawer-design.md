# Mobile chrome relocation + unified workspace drawer design

**Date:** 2026-07-31  
**Status:** Approved for planning  
**Problem:** On mobile, the home title bar packs SSH/work-environment, pane visibility toggles, notifications, and settings into the right chrome. That overflows narrow widths and fights the compact Apifox-style bar. Left/right IDE panes already become overlays on narrow viewports, but they still slide in from opposite sides with separate title-bar toggles—awkward for one-handed use.

**Builds on:** `HomeTitleBar`, `HomeSidebar`, `WorkspaceSidebar`, `WorkspaceShellPaneVisibilityToggles`, `AndroidWorkEnvironmentSelector`, `NotificationBellButton`, `showWorkspaceSettingsDialog`, `PaneOverlayHost`, `WorkspaceIdeShell`, `LayoutCubit` (`sidebarVisible` / `rightToolsVisible` / `narrowLeftSuppressed`).

## Goal

On **mobile / narrow** layouts only:

1. **Clear the title-bar trailing tool cluster** (SSH/work-environment selector, pane toggles, notifications, settings, and `trailingActions`).
2. **Relocate settings + notifications** into sidebar footers (inline trailing icons).
3. **Replace dual side overlays + title-bar pane toggles** with one **unified workspace drawer** whose top **聊天 / 工具** switch swaps body content; the chat workbench stays the main surface underneath.
4. **Remove the title-bar SSH/work-environment entry**; SSH profile management remains available via settings (`/config/ssh-profiles`).

Desktop / wide layouts keep the current dual-pane chrome and title-bar tools.

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Scope | Mobile / narrow only (`TpSidebarScope.isMobile` / IdeShell narrow); desktop unchanged |
| Title bar trailing | Hide **all** right tools on mobile, including `trailingActions` and `AndroidWorkEnvironmentSelector` (mobile title bar no longer exposes Run) |
| Title bar leading open | On mobile, **always** show the sidebar/drawer hamburger (`TpSidebarTrigger` / equivalent)—including when a workspace tab is active. Update `homeSidebarTriggerVisible` (today it is `isMobile && activeTabKey == null` only for home). Workspace open no longer relies on pane toggles |
| SSH entry | Remove from title bar only; keep `/config/ssh-profiles` (and existing settings paths). Do not delete Termux/SSH runtime |
| Home footer | Inline 🔔 + ⚙ on the right of the **供应商** (`Providers`) row |
| Workspace footer | Owned by the **unified drawer shell** (not duplicated inside embedded bodies). Inline 🔔 + ⚙ on the right of **工作区管理**; visible in **both** chat and tools modes. Embedded `WorkspaceSidebar` uses `embedFooter: false` when hosted in the drawer |
| Chat / Tools switch semantics | **Same drawer body swap**: chat = session sidebar; tools = existing right-tools panel content |
| Main surface | Always the chat workbench; tools never take over the center |
| Drawer host | New unified mobile overlay host (extend or replace narrow use of `PaneOverlayHost`) — single slide-in, not left+right opposing overlays |
| Mode persistence | In-memory for the session (remember last mode across open/close); no prefs persistence in v1 |
| LayoutCubit mapping | Keep using `sidebarVisible` / `rightToolsVisible` as intent storage; UI renders one host. open+chat → sidebar intent; open+tools → right-tools intent; closed → both dismissed |

## Non-goals

- Changing desktop title-bar or dual-pane behavior
- Redesigning the right-tools panel internals
- Persisting drawer mode across cold start
- Removing SSH/Termux runtime or settings pages
- Adding Chat/Tools switch to the home (library) sidebar
- Changing what “工作区管理” navigates to

## Invariants

1. **Mobile title bar trailing is empty** of tool chrome (no SSH selector, pane toggles, bell, settings, or trailing action widgets).
2. **Mobile title bar always exposes a leading hamburger** on home and workspace; workspace hamburger opens the unified drawer (sole open affordance after pane toggles are removed).
3. **Settings and notifications remain reachable** on mobile via sidebar/drawer footer icons; they call the same entry points as today (`showWorkspaceSettingsDialog`, `NotificationBellButton` behavior).
4. **Narrow workspace overlay is one drawer** with a top segmented switch; body is either the workspace sidebar content or the right-tools content, never both side-by-side in the overlay.
5. **Footer chrome is shared** across chat/tools modes and owned by the drawer shell (工作区管理 + 🔔 + ⚙); no double footer.
6. **Wide layout ignores** mobile drawer mode and continues docked left/right panes with existing visibility prefs.
7. **SSH capability is not deleted**—only the title-bar launcher is removed on mobile (and the whole trailing cluster is mobile-hidden).

## Design

### 1. Title bar (`HomeTitleBar`)

When `isMobile` (via `TpSidebarScope`):

- Do not build the trailing `ConstrainedBox` / `FittedBox` tool row contents that currently include:
  - `AndroidWorkEnvironmentSelector`
  - `widget.trailingActions` (including Run toolbar — no alternate mobile title-bar entry in v1)
  - `WorkspaceShellPaneVisibilityToggles`
  - `NotificationBellButton`
  - settings `TpIconButton`
- **Always show** the leading mobile drawer trigger (`TpSidebarTrigger`), on both home and active workspace tabs.
  - Change `homeSidebarTriggerVisible` from `isMobile && activeTabKey == null` to **`isMobile`** (or equivalent).
  - On home: trigger opens the existing home `TpSidebar` drawer.
  - On workspace: trigger opens the **unified workspace drawer** (last mode, default chat)—this replaces the removed pane-visibility toggles as the sole open affordance.

Desktop path unchanged.

### 2. Home sidebar footer

In `HomeSidebar`, on mobile only, change the bottom `_ProvidersButton` row into a horizontal layout:

- Leading / center: existing Providers affordance (tap → `HomeGlobalView.providers`)
- Trailing: `NotificationBellButton` + settings icon → `showWorkspaceSettingsDialog`

Desktop Providers button stays as today (no trailing icons required).

### 3. Workspace footer (drawer shell)

The **工作区管理 + 🔔 + ⚙** row lives on the **unified drawer shell**, not independently on each body:

- Tap **工作区管理** → workspace manage (`view=manage`) as today
- Trailing 🔔 / ⚙ → notifications / settings; do **not** navigate to manage
- Visible in both chat and tools modes

Desktop `WorkspaceSidebar` keeps its existing manage tile (icon+label only, no trailing icons). When the sidebar is embedded as the chat body inside the mobile drawer, pass `embedFooter: false` so the shell footer is the only instance.

### 4. Unified mobile workspace drawer

Introduce a narrow-only host (working name: `MobileWorkspaceDrawerHost`) used by `WorkspaceIdeShell` instead of dual `PaneOverlayHost` left/right slides when `_narrow`:

```text
┌─────────────────────────────┐
│ [ 聊天 | 工具 ]  Switch     │
├─────────────────────────────┤
│                             │
│  body: WorkspaceSidebar     │  ← mode=chat (embedFooter: false)
│     or RightToolsPanel      │  ← mode=tools
│                             │
├─────────────────────────────┤
│ 工作区管理          🔔  ⚙   │  shell-owned shared footer
└─────────────────────────────┘
```

**Open / close**

- Open: title-bar hamburger (always present on mobile workspace) and any existing sidebar-open intents → drawer open, restore last `mobileDrawerMode` (default `chat`)
- Switch: change mode only; keep overlay open; update LayoutCubit intents to match
- Dismiss (scrim / back): close overlay; remember mode; clear both side intents / suppress as today

**Content ownership**

- Drawer shell owns Switch + shared footer
- Chat body = workspace sidebar session/worktree chrome with `embedFooter: false`
- Tools body = existing right-tools widget (no second footer)

**LayoutCubit mapping (narrow)**

| UI state | Intent |
|----------|--------|
| closed | sidebar hidden + right tools hidden (and/or narrow suppress) |
| open + chat | `sidebarVisible=true`, right tools overlay off |
| open + tools | right tools visible (or landing override when compose landing), sidebar overlay off |

Wide mode never reads `mobileDrawerMode`.

### 5. SSH / work environment

- Stop placing `AndroidWorkEnvironmentSelector` in `HomeTitleBar` on mobile (covered by trailing hide).
- Users manage SSH profiles through settings → existing `/config/ssh-profiles`.
- No new settings page required in v1 if the route already exists and is reachable from the settings dialog.

### 6. Testing

| Case | Expect |
|------|--------|
| Mobile title bar | No trailing tool widgets; hamburger present on home **and** active workspace |
| Desktop title bar | Unchanged tools present |
| Home mobile footer | Providers row shows 🔔⚙; taps open notifications/settings |
| Workspace hamburger | Opens unified drawer (not home library drawer) |
| Workspace mobile footer | Shell footer shows 工作区管理 + 🔔⚙ in both modes; manage tap still navigates manage; no double footer |
| Drawer switch | Chat↔tools swaps body without dismiss |
| Re-open | Restores last mode |
| Scrim dismiss | Closes drawer |
| Wide IdeShell | Docked dual panes; no unified drawer host |

## Open follow-ups (out of v1)

- Persist `mobileDrawerMode` in layout prefs
- Optional Termux-only compact entry elsewhere if Android users still need a one-tap work-home switch after title-bar removal (not requested; defer)
