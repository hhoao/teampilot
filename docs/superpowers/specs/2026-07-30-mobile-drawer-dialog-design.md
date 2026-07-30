# Mobile drawer width + page Dialogs (TeamPilot)

**Date:** 2026-07-30  
**Status:** Approved (spec review); awaiting user review of written file  
**Product:** TeamPilot (`client/`)  
**Package:** `shared_ui` (Tp* design system) + teampilot hosts  
**Builds on:** [2026-07-29-mobile-hidden-drawer-design.md](./2026-07-29-mobile-hidden-drawer-design.md)  
**Owner choices:** Approach A (design-system APIs); left + right drawers at 80% width; large management Dialogs → full page on narrow; sidebar Dialogs → nav list → detail; small confirms stay card; prefer best architecture / UX / extensibility over workload.

## Problem

1. **Drawer width** — Mobile `TpSidebar` drawers use a fixed `widthMobile = 288`, which feels narrow on phones and tablets. Right tools still use desktop `rightToolsWidth` via `PaneOverlayHost`, so left and right overlays look inconsistent.
2. **Large Dialogs** — Management Dialogs (`showSettingsDialog`, automations, expert/team editors, run configs, …) stay centered cards with desktop insets on narrow viewports, wasting space and fighting touch targets.
3. **Sidebar Dialogs** — Dual-pane Dialogs (left nav + right body) are unusable on narrow: the split is crushed. Users need a **nav page → content page** flow instead of a squeezed Row.

## Goals

1. Narrow left **and** right side panels use a **drawer-like overlay at ~80% of viewport width**.
2. Large management Dialogs use **full-bleed page presentation** on narrow; keep desktop card layout on wide.
3. Dual-pane (nav + body) Dialogs use a shared **`TpDialogNavShell`**: narrow = list then push detail; wide = side-by-side.
4. Small confirms / short prompts remain centered **card** Dialogs.
5. Behavior lives in **`shared_ui`** with explicit presentation APIs (no size heuristics); hosts opt in.
6. Breakpoint stays TeamPilot **`840`** (`WorkspacePanePolicy.narrowBreakpointWidth`), consistent with the hidden-drawer spec.

## Non-goals

- Redesigning Apifox sidebar visual content.
- Migrating right tools into `TpSidebar` (keep `PaneOverlayHost` for the right side to avoid left-edge gesture conflict — same as 2026-07-29).
- Forcing every `showDialog` / `TpDialog` to page mode.
- Changing desktop/wide permanent rail or card Dialog chrome.
- Persisting drawer open state.
- Replacing route-level hub pages (`WorkspaceHubPage`) or **Android hub `GoRouter` settings** (`useAndroidHubNavigation`) with Dialog NavShell — those paths are already full pages.
- Right-edge edge-open for tools overlay (right still opens only from chrome / prefs; dismiss via scrim / back — same as 2026-07-29).

## Decisions

| Topic | Choice | Why |
|-------|--------|-----|
| Architecture | Extend `shared_ui` (`TpSidebarTheme`, page route helper, `TpDialogNavShell`); hosts wire opt-in | Best extensibility; one behavior for Home / Workspace / settings-dialog path |
| Drawer width | Relative: `viewportWidth * widthMobileFraction` (default **0.8**); optional **`widthMobileOverride`** for fixed px | Matches reference UX; avoids clashing with legacy `widthMobile` |
| Legacy `widthMobile` | Keep field for huji / old call sites; **teampilot theme sets `widthMobileOverride`-path as default** (see Theme) | Clear migration; fraction becomes TeamPilot default |
| Left drawer | Existing `TpSidebar` + `TpSidebarMobileDrawer`; only width formula changes | Already the left-nav system |
| Right drawer | Keep `PaneOverlayHost`; on narrow use same fraction from `TpTheme.sidebarTheme` | Visual parity; no second left-edge gesture stack |
| Dialog modes | Explicit `TpDialogPresentation.card` (default) \| `.page` via `showTpDialog` | No heuristics |
| Page shell widget | **`TpDialogPageShell`** = optional chrome for simple page Dialogs; **`TpDialog` stays card-only** | Avoid dual page implementations on `TpDialog` |
| Page route | `showGeneralDialog` mounts a **fullscreen surface only** (Material + size + zero inset + safe-area padding for the *surface*). **App bar is not automatic.** | Lets NavShell own its bars without double chrome |
| Page chrome ownership | Simple pages wrap body in **`TpDialogPageShell(title, …)`**. **`TpDialogNavShell` owns all narrow top bars** (nav + detail) and must **not** be wrapped in `TpDialogPageShell`. | Fixes double app-bar / missing back |
| Page route (wide) | Constrained card as today | Desktop unchanged |
| Dual-pane Dialogs | `TpDialogNavShell` + nested `Navigator` on narrow | Clean back stack |
| Small Dialogs | Stay `card` / existing `showDialog`+`TpDialog` | Avoid full-screen delete confirms |
| Deep link into section | Narrow opens detail first; back → nav list → back → dismiss Dialog | Predictable; no open-ended product override in v1 |
| Close (X) on detail | Dismisses entire Dialog | “Leave settings”, not “leave section only” |
| Android settings | Unchanged `context.push('/config/…')`; NavShell applies to **dialog hosts** (non-Android narrow / desktop modal) | Avoid duplicate page stacks |
| Workload | Prefer architecture quality over incremental patches | Owner direction |

## Architecture

```
shared_ui
  TpSidebarTheme
    widthMobileFraction (default 0.8)
    widthMobileOverride (double?, default null)  ← fixed px when set
    widthMobile (legacy double; see resolution below)

  TpSidebarMobileDrawer
    width = resolveMobileDrawerWidth(theme, screenWidth)

  TpDialogPresentation { card, page }

  showTpDialog(...)
    narrow+page → showGeneralDialog → fullscreen surface (builder owns chrome)
    else        → showDialog → TpDialog (card)

  TpDialogPageShell   ← simple page title/close only (never wrap NavShell)
  TpDialogNavShell    ← owns nav/detail bars on narrow; dual pane on wide

  Back priority (top route wins):
    NavShell detail → NavShell nav → dismiss dialog route
    (Dialog above drawer: back does not close drawer first)

teampilot hosts
  Home / Workspace left     ← TpSidebar (resolved width)
  Workspace right tools     ← PaneOverlayHost(width: fraction * vw from theme)
  showSettingsDialog        ← showTpDialog(page) + TpDialogNavShell
  Android hub settings      ← GoRouter pages (out of NavShell scope)
  Large editors / lists     ← showTpDialog(page)
  Confirms / prompts        ← card (unchanged)
```

### Responsibility split

| Layer | Owns | Does not own |
|-------|------|--------------|
| `shared_ui` | Drawer width resolution, page vs card routes, `TpDialogPageShell`, `TpDialogNavShell` layout/back, generic entry labels via `BuildContext` builders, theme tokens | Which Dialog is “large”; GoRouter tables; right-tools content; `AppLocalizations` |
| teampilot | Opt-in `showTpDialog` / NavShell; map `SettingsDialogEntry` → generic entries; PaneOverlayHost narrow width from theme; Android hub routes stay as today | Reimplementing drawer/page layout per screen |

## Section 1 — Drawer width (left + right)

### Theme & width resolution

```dart
TpSidebarTheme(
  widthMobileFraction: 0.8,       // default
  widthMobileOverride: null,      // if non-null → fixed px (tests / rare)
  widthMobile: 288,               // legacy; ignored when fraction path is active
)
```

**Resolution (single function, used by drawer + documented for hosts):**

```text
if (widthMobileOverride != null)
  drawerWidth = widthMobileOverride
else
  drawerWidth = screenWidth * widthMobileFraction
```

**Migration:**

- TeamPilot `TpTheme` / sidebar theme: rely on fraction (`widthMobileOverride: null`); do **not** pass a fixed override in production.
- huji (or any host wanting today’s 288): set `widthMobileOverride: 288` until it opts into fraction.
- Deprecate relying on legacy `widthMobile` for mobile overlay width in docs; keep the field until huji migrates so shared package API does not hard-break.

Edge drag, scrim, Trigger, and back-to-close are unchanged from the 2026-07-29 spec. Update edge-drag tests that hard-code 288 to use override or assert `0.8 * width`.

### Right tools (`PaneOverlayHost`)

On narrow (`effective.isNarrow`):

```text
rightWidth = MediaQuery.sizeOf(context).width
           * TpTheme.of(context).sidebarTheme.widthMobileFraction
```

(If `widthMobileOverride` is set on theme, use that fixed width instead — same resolver as left.)

- Do **not** hardcode `0.8` in `PaneOverlayHost`.
- Do **not** use `LayoutPreferences.rightToolsWidth` for overlay width on narrow.
- Wide: unchanged docked width from prefs.
- Right overlay: chrome open / scrim dismiss / back only — **no right-edge edge-open**.

## Section 2 — Large Dialog page presentation

### API

```dart
enum TpDialogPresentation { card, page }

Future<T?> showTpDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  TpDialogPresentation presentation = TpDialogPresentation.card,
  double mobileBreakpoint = 768, // teampilot always passes 840
  bool barrierDismissible = true, // page+narrow: recommend false for settings
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Color? barrierColor,
});
```

**Narrow detection:** `MediaQuery.sizeOf(context).width < mobileBreakpoint`.

**Fork:**

| Condition | Implementation |
|-----------|----------------|
| `presentation == page` && narrow | `showGeneralDialog` → fullscreen **surface** (full size, zero inset/radius). **`builder` is the body** — no automatic title bar. |
| else | `showDialog` → `builder` returns / wraps **`TpDialog`** (card) |

**Chrome ownership (narrow + page):**

| Host content | Who draws title / close / back |
|--------------|--------------------------------|
| Simple large form / list | Caller wraps with **`TpDialogPageShell(title:, onClose:, child:)`** inside `builder` |
| **`TpDialogNavShell`** | **NavShell only** — nav list bar and detail bar (leading back). Do **not** wrap NavShell in `TpDialogPageShell`. |

`TpDialog` itself does **not** gain a `presentation` flag.

### Hosting examples

```dart
// Simple large Dialog
showTpDialog(
  context: context,
  presentation: TpDialogPresentation.page,
  mobileBreakpoint: 840,
  barrierDismissible: false,
  builder: (ctx) => TpDialogPageShell(
    title: 'Automations',
    child: AutomationsBody(...),
  ),
);

// Dual-pane → NavShell owns chrome
showTpDialog(
  context: context,
  presentation: TpDialogPresentation.page,
  mobileBreakpoint: 840,
  barrierDismissible: false,
  builder: (ctx) => TpDialogNavShell(
    navTitle: (c) => '...',
    mobileBreakpoint: 840,
    entries: [...],
  ),
);
```

### `TpDialogPageShell` (simple page chrome only)

Hard rules (testable):

- Used **only** for simple (non-NavShell) page Dialogs.
- Fills the overlay size when placed as the `showGeneralDialog` child.
- **No** card border radius; relies on parent surface for zero gutter.
- Top: `SafeArea(top: true)` app bar row — title + close (+ optional trailing).
- Body: `SafeArea(bottom: true)` (or padding from `MediaQuery.padding.bottom`); scrolls; keyboard insets handled by the scrollable body (`viewInsets`).
- Footer actions: use `TpDialogPinnedLayout` inside the shell when needed so actions stay above the home indicator.
- System back / close → pop the dialog route (`Navigator.pop`).
- Default `barrierDismissible` for settings-like hosts: **false** (host passes explicitly).

### Wide + `page`

Still a constrained **card** (`maxWidth` / `maxHeight` as today).  
**Wide + page + NavShell** = card containing side-by-side nav|body — not a fullscreen page.

### Classification (host policy)

| Kind | Presentation | Examples |
|------|----------------|----------|
| Small | `card` | Delete confirm, short alerts, `showTpTextPromptDialog`, SSH host-key prompt |
| Large management | `page` | See **Appendix A** |

## Section 3 — `TpDialogNavShell` (nav → detail)

### API draft

```dart
class TpDialogNavEntry {
  const TpDialogNavEntry({
    required this.icon,
    required this.navLabel,   // String Function(BuildContext)
    required this.title,      // String Function(BuildContext)
    required this.subtitle,   // String Function(BuildContext)
    required this.bodyBuilder,
  });
  // …
}

class TpDialogNavShell extends StatelessWidget {
  const TpDialogNavShell({
    required this.navTitle,          // String Function(BuildContext)
    required this.entries,
    this.initialIndex = 0,
    this.mobileBreakpoint = 768,     // teampilot passes 840
    this.onClose,                    // defaults to Navigator.pop
    // …
  });
}
```

- **l10n:** entries use `String Function(BuildContext)` / `WidgetBuilder` only — no `AppLocalizations` in `shared_ui`. Teampilot `SettingsDialogEntry` adapts `(l10n) => …` → `(ctx) => …(ctx.l10n)`.
- **Breakpoint:** NavShell’s own `mobileBreakpoint` parameter; teampilot always passes `WorkspacePanePolicy.narrowBreakpointWidth` (**840**), same value as `showTpDialog`. No third breakpoint constant.
- **Hosting:** `showTpDialog(presentation: page, …, builder: (_) => TpDialogNavShell(...))` — **without** wrapping in `TpDialogPageShell`. On narrow, NavShell paints SafeArea + nav/detail app bars itself; on wide, NavShell is the card body (side-by-side) and the outer route is still the constrained card from `showTpDialog`.
- **Narrow SafeArea:** NavShell applies the same top/bottom safe-area rules as `TpDialogPageShell` (status bar / home indicator), so page and nav hosts feel identical at the edges.

### Behavior

| Viewport | Layout |
|----------|--------|
| Wide (`width >= mobileBreakpoint`) | Persistent left nav + right body |
| Narrow | Nested `Navigator`: **nav list** ↔ **detail** |

### Narrow navigation rules

1. Default: nav list (`navTitle`; close → dismiss Dialog).
2. Tap entry → update selection + push detail (entry `title`; leading back → pop to nav).
3. System back: detail → nav → dismiss Dialog.
4. `initialIndex` / deep link: open **detail first**; back → nav list; back again → dismiss.
5. Close (X) on detail → dismiss **entire** Dialog.

### Settings scope split

| Path | Behavior under this spec |
|------|--------------------------|
| `useAndroidHubNavigation` → `GoRouter` `/config/…` | **Out of scope** (already page navigation). Do not wrap in NavShell. |
| `showSettingsDialog` / `showWorkspaceSettingsDialog` | Migrate to `showTpDialog(page)` + `TpDialogNavShell`. |

Tests must cover both matrices separately so Android routes are not “fixed” by Dialog NavShell work.

### Other dual-pane Dialogs

Migrate semantic “section list + body” Dialogs to `TpDialogNavShell`. Single-page forms use Section 2 only.

## Back-stack priority

When multiple overlays exist, the **topmost route** handles back:

1. `TpDialogNavShell` detail (if pushed)  
2. Else dismiss the dialog route (nav list or card/page dialog)  
3. Else `TpSidebar` openMobile (07-29 rule)  
4. Else app route pop  

A dialog above an open drawer: first back closes dialog (or its detail), not the drawer.

## Testing

### shared_ui

- Drawer width = `0.8 * screenWidth` when override is null; `widthMobileOverride` wins.
- Breakpoint flip still mounts/unmounts overlay (regression from 2026-07-29).
- `showTpDialog(page)` narrow: fullscreen surface, zero inset; with `TpDialogPageShell` → title+close SafeArea; with `TpDialogNavShell` alone → no double app bar, detail has back.
- Nested NavShell: must not be wrapped in `TpDialogPageShell` (widget test / doc assert via example).
- `showTpDialog(page)` wide: constrained card, not full-bleed.
- `showTpDialog(card)` narrow: centered card with maxWidth.
- `TpDialogNavShell`: wide side-by-side; narrow list → detail → back → list → dismiss; X on detail pops Dialog; `initialIndex` opens detail with back-to-list.
- Nested back: detail present → first back does not dismiss Dialog.

### teampilot

- Home / Workspace left drawer ≈ 80% width.
- Workspace right tools overlay ≈ 80% from theme fraction; docked prefs width on wide.
- Settings **dialog** path: narrow nav → section; wide dual pane.
- Android **hub** settings still use GoRouter (smoke: push `/config/layout` still works).
- One Appendix A Dialog uses page; one confirm stays card.
- Wide/desktop regression: rails, card Dialogs, right-tools prefs width.

## Migration

1. Add `widthMobileFraction` + `widthMobileOverride` and shared resolver; TeamPilot uses fraction; document huji override `288`; update 288-hardcoded tests.
2. Workspace IDE: narrow `PaneOverlayHost` width via theme resolver (no hardcoded 0.8).
3. Add `TpDialogPageShell` + `showTpDialog`; migrate Appendix A entry points.
4. Add `TpDialogNavShell`; rewrite `showSettingsDialog` adapter; leave Android hub routes alone.
5. Sweep remaining dual-pane onto NavShell / remaining Appendix A onto page; confirms stay card.
6. Document in `shared_ui` README (fraction, override, `showTpDialog`, NavShell, Android vs dialog settings).

## Success criteria

- Narrow left and right drawers use the same resolved width (~`0.8 * viewport`, or override when set).
- Narrow + `presentation: page`: zero dialog inset, full route size, SafeArea chrome, close pops — objectively checked in widget tests.
- Narrow + `card`: remains centered with maxWidth.
- Settings dialog path: list → detail on narrow without dual-pane crush; Android hub routes unchanged.
- Wide: rails / card Dialogs / docked right tools / NavShell dual-pane-in-card unchanged in behavior.
- New surfaces opt into page / NavShell without copying mobile layout code.

## Appendix A — First-wave `presentation: page` call sites

Migrate these (or their `show*` wrappers) in the first implementation wave; everything else stays `card` until explicitly opted in:

| Surface | Notes |
|---------|--------|
| `showSettingsDialog` / `showWorkspaceSettingsDialog` | + `TpDialogNavShell` |
| `AutomationsDialog` / `AutomationEditorDialog` | List + editor |
| `ExpertEditorDialog` | Large form |
| Team create / large team settings dialogs (`home_workspace_new_team_dialog`, landing team settings when modal) | Management |
| `RunConfigurationsDialog` / `RunConfigEditorDialog` | Management |
| Large SSH profile form / MCP connect forms when shown as modal | Multi-field |
| `workspace_search_dialog` | Management search surface |

**Explicitly stay `card`:** delete confirms, `showTpTextPromptDialog`, short alerts, SSH host-key prompt, one-shot yes/no dialogs.
