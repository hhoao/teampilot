# Mobile hidden drawer (TpSidebar) for TeamPilot Android / narrow

**Date:** 2026-07-29  
**Status:** Approved (spec review fixes applied)  
**Product:** TeamPilot (`client/`)  
**Package:** `shared_ui` (Tp* design system — introduce / align `TpSidebar*`)  
**Reference:** huji `docs/superpowers/specs/2026-07-20-tp-sidebar-design.md`; [shadcn Sidebar](https://ui.shadcn.com/docs/components/base/sidebar)

## Problem

On Android (and other narrow viewports), TeamPilot keeps a permanent left rail:

- **Home** — `HomePage` always mounts `TwoPaneSplitView` + `HomeSidebar`, consuming ~⅓ of the screen and crushing the main pane (e.g. automations empty state).
- **Workspace** — narrow mode already overlays sides via `PaneOverlayHost`, but Home / hub shells do not share that model; left-nav UX is inconsistent.
- **Hub / settings** — `_settingsChromeShell` has AppBar chrome and `AndroidShellChrome.shouldHideDrawer`, but no real drawer; `WorkspaceDrawer` exists and is unused.

Users need a **hidden drawer**: full-width content by default, open nav via hamburger + edge swipe, keep the existing Apifox sidebar look (not a card-grouped redesign).

## Goals

1. Narrow viewports: left nav is a **modal drawer** (scrim + slide-in), not an in-flow column.
2. Open via **hamburger** (`TpSidebarTrigger`) **and** **left-edge drag** (Material Drawer–grade gesture).
3. Cover **all Android / narrow left nav surfaces**: Home, Workspace session rail, hub/settings chrome.
4. Preserve **existing sidebar visual content** (Apifox list / selected row chrome) — style option A.
5. Land **`TpSidebar*`** in teampilot’s `shared_ui` (align with huji API), so shell chrome is design-system owned; product widgets stay content-only.
6. Breakpoint by **width**, not hard-coded `Platform.isAndroid` only — phone portrait drawer; wide tablet can keep permanent rail. **TeamPilot hosts use a single threshold: 840** (`WorkspacePanePolicy.narrowBreakpointWidth`) so Home and Workspace flip together.

## Non-goals

- Card-grouped / Xiaohongshu-style drawer redesign.
- Persisting open/collapsed preference.
- Migrating right-tools overlay into `TpSidebar` (keep `PaneOverlayHost` for the right side).
- Fully rewriting desktop sidebars into `TpSidebarMenu*` atoms in this delivery (desktop may keep current widgets inside / beside Tp shell; incremental later).
- Pixel-matching shadcn web demo.

## Decisions

| Topic | Choice | Why |
|-------|--------|-----|
| Approach | `TpSidebar*` in `shared_ui` + teampilot host wiring | Best architecture / extensibility vs one-off `Scaffold.drawer`; shared with huji |
| Visual | Keep existing Apifox sidebar content | Owner choice A; minimal product visual churn |
| Open | Hamburger + edge swipe | Owner choice B; Material-grade UX |
| Scope | Home + Workspace left + hub/settings on **narrow width and/or Android shell** | Owner choice C |
| Breakpoint | TeamPilot **`mobileBreakpoint: 840`** everywhere left nav flips (Home, Workspace, shared Provider). `TpSidebar` package default may stay 768 (huji parity); teampilot always overrides to 840. | Align with existing `WorkspacePanePolicy.narrowBreakpointWidth`; avoid 768–839 Home/Workspace mismatch |
| Mobile presentation | Overlay drawer with edge-drag in `TpSidebar`, not raw `Scaffold.drawer` as the long-term API | One API for desktop+mobile; host does not nest competing drawers |
| Workspace left | Narrow left rail → TpSidebar drawer; retire left `PaneOverlayHost` path | One left-drawer system |
| Workspace visibility | Narrow: map `LayoutCubit.sidebarVisible` ↔ `TpSidebarScope.openMobile` (toggle / dismiss / Trigger). Wide: keep today’s docked visibility prefs | Preserve existing hamburger / preference behavior |
| Workspace right | Keep `PaneOverlayHost` | Out of scope; avoid left-edge gesture conflict |
| Hub chrome | Apply drawer shell where `_settingsChromeShell` already special-cases Android; also honor width < 840 if that shell is shown on a narrow desktop window. **Do not** change inner hub split breakpoints (`WorkspaceSplitShell` 820) in this delivery | Shell drawer ≠ inner two-pane compact |
| Hub drawer content | Reuse **Home global nav** (`HomeSidebar` content / shared entries), not a second ad-hoc list | One nav model; avoid overlapping `ConfigSettingsHubPage` body lists |
| Hub detail | `AndroidShellChrome.shouldHideDrawer` | No trigger / no edge-open on detail; back owns leading |
| Close on navigate | Host calls `setOpenMobile(false)` after nav | Package stays router-agnostic |
| Unused `WorkspaceDrawer` | Replace with Tp composition or thin wrapper, then remove dead Material-only helper | Avoid two drawer stacks |

## Architecture

```
shared_ui
  TpSidebarProvider          ← open / openMobile / breakpoint / shortcut
  ├── TpSidebar              ← desktop width; mobile ~0 in-flow + drawer overlay (+ edge drag)
  ├── TpSidebarTrigger       ← hamburger
  ├── TpSidebarInset         ← main content chrome (optional)
  └── TpSidebarScope         ← toggle / setOpenMobile

teampilot hosts
  HomeShell / HomePage       ← narrow: Provider + Trigger + drawer(HomeSidebar content)
  Workspace IDE shell        ← narrow left: TpSidebar; right: PaneOverlayHost
  _settingsChromeShell       ← AppBar Trigger + drawer nav; detail hides drawer
```

**Responsibility split**

| Layer | Owns |
|-------|------|
| `shared_ui` | Layout, collapse, mobile drawer, edge gesture, scrim, back-to-close, theme tokens, scope |
| teampilot | Nav labels/routes, selected state, placing Trigger, closing drawer after navigation, hub hide rules |

### Narrow vs wide

| Viewport | Left nav | Main |
|----------|----------|------|
| Wide (`width >= 840` in teampilot) | In-flow rail (existing TwoPane / IDE split, or Tp desktop mode) | Normal |
| Narrow (`width < 840`) | `TpSidebar` reserves ~0 width; panel in overlay drawer | Full bleed |

### Gestures and dismiss

| Action | Behavior |
|--------|----------|
| Tap Trigger | Toggle `openMobile` |
| Drag from left edge | Follow finger; release past threshold → open, else snap closed |
| Tap scrim | `setOpenMobile(false)` |
| System back while open | Close drawer first (do not pop route) |
| Nav item pressed | Host closes drawer after selection / route change |
| Drag drawer closed | Snap shut |

Edge-open must **not** fire on hub detail routes when drawer is hidden.

### Surface wiring

**Home**

- Wide: keep `TwoPaneSplitView` + `HomeSidebar` behavior.
- Narrow: do not reserve sidebar width; put `TpSidebarTrigger` on title / shell chrome; drawer child = same sidebar content (extract layout-agnostic content if needed so padding/width tokens work in drawer).

**Workspace**

- Wide: unchanged docked left pane.
- Narrow: left session list via TpSidebar drawer (hamburger + edge); **replace** `PaneOverlayHost` left overlay path so only one left drawer exists.
- Right tools: still `PaneOverlayHost`.

**Hub / settings (`_settingsChromeShell`)**

- When the Android (or narrow) shell is active: AppBar leading = Trigger when not detail; drawer content = **same Home global nav content** (not a separate menu taxonomy).
- Detail (`shouldHideDrawer`): leading = back; no edge-open; no Trigger.
- Inner hub pages that use `WorkspaceSplitShell` keep their own 820 compact breakpoint for *content* splits; that is unrelated to the shell left drawer.

## Data / API notes

- Prefer porting / aligning the huji `TpSidebar*` public API rather than inventing a parallel teampilot-only drawer API.
- **Required `shared_ui` mobile enhancements** (explicit work, not optional polish): **left-edge drag**, **system back closes drawer** (`PopScope` or equivalent), optional velocity fling; host must be able to **disable edge-open** when hub detail hides the drawer.
- No new persistence keys. No router types inside `shared_ui`.

## Testing

**shared_ui**

- Breakpoint flip: wide→narrow unmounts in-flow width; narrow→wide restores.
- Trigger toggles `openMobile`; scrim dismiss; back dismiss.
- Edge drag: past midpoint opens; below midpoint closes; **disabled when host disables edge-open** (hub detail / `shouldHideDrawer`).
- Opening via edge drag or Trigger on Workspace narrow **writes through** to `LayoutCubit.sidebarVisible` so preference and UI stay aligned; dismiss likewise.

**teampilot**

- Home narrow: no permanent sidebar column; content full width; open drawer shows existing nav look; select item closes drawer.
- Workspace narrow: left drawer via TpSidebar; right overlay still works; left-edge does not open right tools.
- Hub: root shows Trigger + drawer; detail hides drawer and shows back.
- Desktop / wide regression: Home TwoPane widths and workspace docked panes unchanged.

## Migration / cleanup

1. Introduce `TpSidebar*` into teampilot `shared_ui` (sync/port from huji as appropriate), including edge-drag + back-to-close + disable-edge-open.
2. Wire Home narrow shell with `mobileBreakpoint: 840`.
3. Wire Workspace narrow left (drop left `PaneOverlayHost` usage); bridge `sidebarVisible` ↔ `openMobile`.
4. Wire hub chrome (Home nav in drawer) + honor `shouldHideDrawer`.
5. Remove or repurpose unused `WorkspaceDrawer`.

## Success criteria

- On a phone-width viewport, Home main pane is full width until the user opens the drawer.
- Drawer opens from hamburger and from left-edge drag; closes via scrim, back, reverse drag, and after nav.
- Workspace and hub follow the same left-nav model without a second competing left drawer.
- Wide/desktop layouts keep today’s permanent rail behavior.
