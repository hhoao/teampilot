# Workspace narrow left → PaneOverlayHost (parity with right)

**Date:** 2026-07-30  
**Status:** Implemented  
**Product:** TeamPilot (`client/`)  
**Supersedes (workspace left only):** [2026-07-29-mobile-hidden-drawer-design.md](2026-07-29-mobile-hidden-drawer-design.md) decisions that routed **workspace** narrow left through `TpSidebar` / `openMobile`. Home / hub `TpSidebar` drawers are unchanged. Workspace no longer bridges `sidebarVisible` ↔ `openMobile`.

## Problem

On narrow viewports, workspace left and right side panes use different systems:

| Side | Mechanism | Open / close |
|------|-----------|--------------|
| Right | `LayoutCubit` → `PaneOverlayHost` | Title-bar toggle + scrim dismiss |
| Left | Shared HomeShell `TpSidebarProvider.openMobile` via `_WorkspaceMobileSidebarHost` | Toggle calls `scope.toggleSidebar()`; edge drag possible |

That split caused:

1. **Broken left toggle** when kept-alive Home (and inactive workspace tabs) mounted inactive `TpSidebar` hosts that cleared shared `openMobile` (mitigated in `shared_ui` overlay-ownership fix, but the dual system remains fragile).
2. **Asymmetric UX** — users expect the session-list rail to behave like right tools on mobile (button + overlay, no edge swipe).
3. **Bridge complexity** — `sidebarVisible` ↔ `openMobile` sync, force-close on entry, and mobile-only branches in `WorkspaceShellSidebarVisibilityToggle`.

## Goals

1. Narrow workspace **left and right** both use `PaneOverlayHost`, driven by `LayoutCubit` visibility prefs (plus a narrow-only left suppress gate — see Decisions).
2. Open / close left via **title-bar toggle + scrim** only (no left-edge swipe on workspace).
3. On **entering narrow**, suppress the left overlay once without covering the center; right behavior unchanged.
4. Remove workspace dependence on `TpSidebar` / `openMobile` for the session rail.
5. Keep Home (and other) `TpSidebar` drawers as today.

## Non-goals

- Changing Home / settings hub `TpSidebar` drawers or edge-drag.
- Migrating right tools into `TpSidebar`.
- Changing wide (docked) MultiPane layout or prefs schema.
- Reverting the `shared_ui` multi-host overlay-ownership fix (still needed for Home keep-alive).
- Persisting a separate “narrow left forced closed” flag across app restarts.
- Adding `PopScope` / system-back dismiss for `PaneOverlayHost` in this delivery (match current right: scrim + toggle only).

## Decisions

| Topic | Choice | Why |
|-------|--------|-----|
| Approach | Restore workspace narrow left on `PaneOverlayHost` | Same path as right; no shared `openMobile` |
| Open gesture | Toggle button + scrim only | Owner choice; match right |
| Enter-narrow left | **Ephemeral suppress on `LayoutCubit`** (scheme A) — do **not** call `setSidebarVisible(false)` | Same pattern as `landingRightToolsOverride`: title bar + IdeShell both read/write cubit; prefs stay true for return to wide docked left |
| Effective showLeft | `preferences.sidebarVisible && !state.narrowLeftSuppressed` | Policy still exposes intent; shell passes gated `showLeft` |
| Toggle semantics | Drive from **effective** left visibility; open clears suppress then ensures prefs true | Avoid “prefs true + suppressed → tap sets false” dead-toggle; title bar is **not** under IdeShell |
| Width (narrow) | Theme `resolveMobileDrawerWidth` for **both** left and right | Visual parity ([2026-07-30-mobile-drawer-dialog-design.md](2026-07-30-mobile-drawer-dialog-design.md)) |
| Dual overlays | Allow both `showLeft` and `showRight`; scrim dismisses **both** (current `PaneOverlayHost`) | Unchanged host behavior |
| Force-close vs right | Enter-narrow suppress **never** mutates right-tools prefs / landing override | Invariant |
| System back | Not in this delivery | Match right today |
| Home left | Unchanged `TpSidebar` | Out of scope |
| Landing / compose | Left always follows `sidebarVisible` (+ suppress); no landing override | Right keeps existing override |

## Architecture

```
Wide:
  MultiPane(dock left | center | right)     ← sidebarVisible / rightToolsVisible
  PaneOverlayHost(showLeft: false, showRight: false)  // wrapper only; no side children required

Narrow:
  PaneOverlayHost
    showLeft  ← sidebarVisible && !LayoutState.narrowLeftSuppressed
    showRight ← rightToolsVisible (or landing override)
    leftWidth / rightWidth ← theme.resolveMobileDrawerWidth(vw)
    child: MultiPane(center only; sides undocked)
```

### Policy (`WorkspacePanePolicy`)

Narrow effective (replace today’s hard-coded `overlayLeft: false`):

- `dockLeft` / `dockRight`: `false`
- `overlayLeft`: `preferences.sidebarVisible`  (**intent only** — shell may still suppress)
- `overlayRight`: right intent (unchanged)

Wide unchanged.

`overlayLeft` remains the prefs-derived eligibility flag for tests/policy; the shell’s `showLeft` applies the suppress gate.

### Ephemeral suppress owner (`LayoutCubit` / `LayoutState`)

- Add non-persisted `bool narrowLeftSuppressed` on `LayoutState` (mirror `landingRightToolsOverride`: emit-only, never written to prefs JSON).
- APIs: `setNarrowLeftSuppressed(bool)` / `clearNarrowLeftSuppressed()`.
- **Why cubit, not IdeShell State / Inherited under shell:** `WorkspaceShellSidebarVisibilityToggle` lives in `HomeWorkspaceTitleBar`, which is a **sibling** of the body stack — not a descendant of `WorkspaceIdeShell`. Title bar and active shell both already have `LayoutCubit`.
- Scope: **app-global** for the session (one LayoutCubit), same as other layout intents. Acceptable with keep-alive tabs.

### Shell (`WorkspaceIdeShell`)

- Always wrap with `PaneOverlayHost`. On narrow, pass `left:` chrome + content, `showLeft: effective.overlayLeft && !layoutState.narrowLeftSuppressed`, `onDismissLeft → setSidebarVisible(false)` + `clearNarrowLeftSuppressed()`.
- Delete `_WorkspaceMobileSidebarHost` and all `openMobile` ↔ prefs bridging.
- **Enter-narrow suppress (scheme A):**
  - Trigger on transition **`!wasNarrow → isNarrow`** (also treat first build that is already narrow as enter). When **`isNarrow → !isNarrow`**, call `clearNarrowLeftSuppressed()`.
  - On enter: `setNarrowLeftSuppressed(true)`. **Do not** call `setSidebarVisible`.
  - Apply gate **synchronously** in the same build that first observes narrow (read cubit flag that was set in `didChangeDependencies` / size callback **before** building `PaneOverlayHost`, or set suppress in the size→sync path before `showLeft` is computed). No post-frame-only close — avoid one-frame flash.
  - Never touch `rightToolsVisible` / landing override when suppressing.
- Narrow widths: both sides use theme drawer fraction for overlay presentation.

### Toggle (`WorkspaceShellSidebarVisibilityToggle`)

No `TpSidebarScope` branch. Read `LayoutCubit` for both prefs and suppress:

```dart
final effectiveOpen =
    state.preferences.sidebarVisible && !state.narrowLeftSuppressed;
onTap: () {
  final layout = context.read<LayoutCubit>();
  if (effectiveOpen) {
    layout.setSidebarVisible(false);
    layout.clearNarrowLeftSuppressed();
  } else {
    layout.clearNarrowLeftSuppressed();
    layout.setSidebarVisible(true);
  }
}
```

Button chrome (primary vs muted) follows **effectiveOpen**.

### Scrim

Unchanged: tapping scrim calls both dismiss callbacks when both sides are open. Left dismiss also clears suppress (see Shell).

## Testing

| Case | Expect |
|------|--------|
| Policy narrow + `sidebarVisible: true` | `overlayLeft == true` (intent) |
| Policy narrow + hidden | `overlayLeft == false` |
| First narrow pump with prefs left visible | `showLeft` false (suppress); left content **zero frames** visible; prefs still `sidebarVisible: true` |
| Toggle open after suppress | Suppress cleared; left overlay shown; prefs true (no dead-toggle) |
| Dismiss scrim on left | `sidebarVisible: false`; suppress cleared; left hidden |
| wide (`sidebarVisible: true`) → enter narrow | Left overlay not shown; prefs remain true |
| Above then return to wide | `dockLeft == true` |
| Enter narrow while right overlay open | Right prefs / overlay unchanged after left suppress |
| Left + right both open; tap scrim | Both dismiss (current host) |
| Leave narrow and re-enter | Suppress applies again once per sojourn |
| Toggle widget | Does not call `TpSidebarScope`; works without provider openMobile |
| Smoke: right overlay independent when left suppressed | Unchanged |

## Relationship to prior specs

- **2026-07-29 mobile hidden drawer:** Home / hub `TpSidebar` decisions remain. Workspace-left → TpSidebar / retire left `PaneOverlayHost` is **reversed** by this spec.
- **2026-07-30 mobile drawer dialog:** fraction width for overlays still applies; workspace left now consumes the same resolver via `PaneOverlayHost`.

## Success criteria

- Narrow workspace: left and right open/close through the same overlay host; left uses prefs + ephemeral enter-narrow suppress.
- Entering a workspace on phone does not auto-cover the center with the session list; user opens left via the sidebar toggle.
- Returning to wide with `sidebarVisible: true` still docks the left rail (force-close did not write prefs false).
- No workspace code path depends on `TpSidebarScope.openMobile` for the session rail.
- Existing Home narrow drawer (hamburger + edge) still works.
