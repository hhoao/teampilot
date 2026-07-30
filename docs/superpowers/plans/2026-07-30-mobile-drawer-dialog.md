# Mobile Drawer 80% + Page Dialogs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Narrow left/right drawers at 80% viewport width; large management Dialogs as full pages on narrow; dual-pane Dialogs via `TpDialogNavShell` (nav → detail).

**Architecture:** Extend `shared_ui` with drawer width resolver (`widthMobileFraction` + `widthMobileOverride`), `showTpDialog` / `TpDialogPageShell` / `TpDialogNavShell`. Teampilot hosts pass breakpoint `840`, wire right `PaneOverlayHost` width from theme, migrate settings dialog + Appendix A call sites. Android hub `GoRouter` settings stay unchanged.

**Tech Stack:** Flutter; `shared_ui` Tp* design system; TeamPilot `WorkspacePanePolicy.narrowBreakpointWidth` (840); existing `TpSidebar*` / `TpDialog` / `PaneOverlayHost`.

**Spec:** `docs/superpowers/specs/2026-07-30-mobile-drawer-dialog-design.md`

## Global Constraints

- Prefer architecture / UX quality; do not ship half-width drawers or heuristic “auto fullscreen”.
- TeamPilot always passes `mobileBreakpoint: 840` (`WorkspacePanePolicy.narrowBreakpointWidth`).
- `TpDialog` remains **card-only**. Page chrome = `TpDialogPageShell` (simple) or `TpDialogNavShell` (dual-pane). Never wrap NavShell in PageShell.
- Android `useAndroidHubNavigation` → `/config/…` is **out of scope** for NavShell.
- Small confirms stay `card` / existing `showDialog`+`TpDialog`.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` and package + host tests listed in the final task.
- shared_ui tests: `cd client/packages/shared_ui && flutter test …`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/shared_ui/lib/src/theme/components/tp_sidebar_theme.dart` | `widthMobileFraction`, `widthMobileOverride`; `resolveMobileDrawerWidth` |
| `client/packages/shared_ui/lib/src/components/sidebar/tp_sidebar_mobile_drawer.dart` | Use resolver instead of fixed `widthMobile` |
| `client/packages/shared_ui/lib/src/components/dialog/tp_dialog_presentation.dart` | `TpDialogPresentation` enum |
| `client/packages/shared_ui/lib/src/components/dialog/tp_dialog_page_shell.dart` | Simple page title/close + SafeArea |
| `client/packages/shared_ui/lib/src/components/dialog/show_tp_dialog.dart` | `showTpDialog` card vs page fork |
| `client/packages/shared_ui/lib/src/components/dialog/tp_dialog_nav_shell.dart` | Wide dual-pane; narrow nested Navigator |
| `client/packages/shared_ui/lib/shared_ui.dart` | Export new APIs |
| `client/packages/shared_ui/README.md` | Document fraction, page dialog, NavShell |
| `client/lib/pages/workspace_ide/workspace_ide_shell.dart` | Narrow right overlay width from theme resolver |
| `client/lib/widgets/settings/settings_dialog.dart` | `showTpDialog(page)` + `TpDialogNavShell` adapter |
| Appendix A hosts under `client/lib/pages/**` / `widgets/**` | Opt into page (`TpDialogPageShell`) or NavShell per Task 7 table |
| Tests under `client/packages/shared_ui/test/…` and `client/test/…` | See each task |

---

### Task 1: Drawer width resolver (theme)

**Files:**
- Modify: `client/packages/shared_ui/lib/src/theme/components/tp_sidebar_theme.dart`
- Create: `client/packages/shared_ui/test/theme/tp_sidebar_mobile_width_test.dart`

**API:**

```dart
// On TpSidebarTheme:
final double widthMobileFraction; // default 0.8
final double? widthMobileOverride; // default null

/// Shared by left drawer and host right overlay.
double resolveMobileDrawerWidth(double screenWidth) {
  final override = widthMobileOverride;
  if (override != null) return override;
  return screenWidth * widthMobileFraction;
}
```

Keep legacy `widthMobile` field for API stability but **do not use it** in `resolveMobileDrawerWidth` (documented in theme dartdoc). Update `copyWith` / `==` / `hashCode`.

- [ ] **Step 1: Write failing tests**

```dart
test('fraction 0.8 of 400 => 320', () {
  expect(const TpSidebarTheme().resolveMobileDrawerWidth(400), 320);
});
test('override wins over fraction', () {
  expect(
    const TpSidebarTheme(widthMobileOverride: 288).resolveMobileDrawerWidth(400),
    288,
  );
});
```

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client/packages/shared_ui && flutter test test/theme/tp_sidebar_mobile_width_test.dart`

- [ ] **Step 3: Implement theme fields + resolver**

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/shared_ui/lib/src/theme/components/tp_sidebar_theme.dart \
  client/packages/shared_ui/test/theme/tp_sidebar_mobile_width_test.dart
git commit -m "feat(shared_ui): resolve mobile drawer width from fraction"
```

---

### Task 2: Wire drawer + update edge-drag tests

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/sidebar/tp_sidebar_mobile_drawer.dart`
- Modify: `client/packages/shared_ui/test/components/sidebar/tp_sidebar_edge_drag_test.dart` (and any test hard-coding 288 as drawer width)

- [ ] **Step 1: Write / adjust failing test**

In edge-drag suite (MediaQuery width 400): open drawer, expect panel width ≈ `320` (`0.8 * 400`), not 288.

Optional: theme with `widthMobileOverride: 288` still yields 288.

- [ ] **Step 2: Run edge-drag + mobile drawer tests — expect FAIL on width assert**

Run: `cd client/packages/shared_ui && flutter test test/components/sidebar/`

- [ ] **Step 3: Change `_drawerWidth` to**

```dart
double _drawerWidth(BuildContext context) =>
    widget.theme.resolveMobileDrawerWidth(MediaQuery.sizeOf(context).width);
```

Replace all `_drawerWidth` getters that read `theme.widthMobile`.

- [ ] **Step 4: Run sidebar tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/shared_ui/lib/src/components/sidebar/tp_sidebar_mobile_drawer.dart \
  client/packages/shared_ui/test/components/sidebar/
git commit -m "feat(shared_ui): mobile drawer uses fractional width"
```

---

### Task 3: Workspace right overlay width

**Files:**
- Modify: `client/lib/pages/workspace_ide/workspace_ide_shell.dart` (`_buildPaneHost`, ~613–617)
- Test: `client/test/pages/workspace_ide/workspace_ide_shell_smoke_test.dart` (extend) **or** new focused test

- [ ] **Step 1: Write failing test**

Pump narrow IDE shell (viewport `< 840`) with right tools visible; find right overlay panel width ≈ `0.8 * viewport` (not `prefs.rightToolsWidth`).

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client && flutter test test/pages/workspace_ide/workspace_ide_shell_smoke_test.dart`

- [ ] **Step 3: Implement**

When `effective.isNarrow`:

```dart
final fractionWidth = TpTheme.of(context)
    .sidebarTheme
    .resolveMobileDrawerWidth(MediaQuery.sizeOf(context).width);
// …
rightWidth: effective.isNarrow ? fractionWidth : prefs.rightToolsWidth,
```

Do not hardcode `0.8`. Left width for unused left overlay can stay as today (`showLeft: false`).

- [ ] **Step 4: Run — expect PASS** (existing smoke tests still green)

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/workspace_ide/workspace_ide_shell.dart \
  client/test/pages/workspace_ide/
git commit -m "feat(workspace): narrow right tools overlay uses drawer fraction"
```

---

### Task 4: `showTpDialog` + `TpDialogPageShell`

**Files:**
- Create: `client/packages/shared_ui/lib/src/components/dialog/tp_dialog_presentation.dart`
- Create: `client/packages/shared_ui/lib/src/components/dialog/tp_dialog_page_shell.dart`
- Create: `client/packages/shared_ui/lib/src/components/dialog/show_tp_dialog.dart`
- Modify: `client/packages/shared_ui/lib/shared_ui.dart` (exports)
- Create: `client/packages/shared_ui/test/components/tp_dialog_page_test.dart`

**API (from spec):**

```dart
enum TpDialogPresentation { card, page }

Future<T?> showTpDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  TpDialogPresentation presentation = TpDialogPresentation.card,
  double mobileBreakpoint = 768,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Color? barrierColor,
});

class TpDialogPageShell extends StatelessWidget {
  const TpDialogPageShell({
    required this.title,
    required this.child,
    this.onClose,
    this.trailing,
    super.key,
  });
  // SafeArea top app bar + body SafeArea bottom; close → onClose ?? Navigator.pop
}
```

**Fork:** narrow + page → `showGeneralDialog` fullscreen surface (Material, size fill, zero inset); else → `showDialog` with builder (card). No automatic app bar in `showTpDialog`.

- [ ] **Step 1: Write failing tests**

1. `page` + width 400: pump `showTpDialog` with `TpDialogPageShell`; assert no dialog inset gutter (find shell fills), SafeArea close pops.
2. `page` + width 900: still constrained / not full-bleed (card path).
3. `card` + width 400: centered `TpDialog` still found.

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client/packages/shared_ui && flutter test test/components/tp_dialog_page_test.dart`

- [ ] **Step 3: Implement presentation, page shell, `showTpDialog`, exports**

`showTpDialog` responsibilities:
- narrow + `page`: `showGeneralDialog` fullscreen surface; **`builder` is mounted as-is** (no automatic app bar).
- else (`card`, or `page` on wide): `showDialog` whose child is the **`builder` result** — callers of simple page-on-wide may still return `TpDialog`/`TpDialogPageShell` content inside a constrained card. For `presentation: page` on wide, wrap builder in a constrained `Dialog`/`TpDialog`-compatible shell so `TpDialogNavShell` sits inside the card (maxWidth/maxHeight as hosts pass via optional params or defaults ~1160×960 for settings-class). Document defaults in dartdoc.

Optional constructor params if needed for wide card size: `maxWidth`, `maxHeight` on `showTpDialog` (defaults: 640 / null for card; larger defaults OK when presentation is page).

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/shared_ui/lib/src/components/dialog/ \
  client/packages/shared_ui/lib/shared_ui.dart \
  client/packages/shared_ui/test/components/tp_dialog_page_test.dart
git commit -m "feat(shared_ui): add showTpDialog page presentation and PageShell"
```

---

### Task 5: `TpDialogNavShell`

**Files:**
- Create: `client/packages/shared_ui/lib/src/components/dialog/tp_dialog_nav_shell.dart`
- Modify: `client/packages/shared_ui/lib/shared_ui.dart`
- Create: `client/packages/shared_ui/test/components/tp_dialog_nav_shell_test.dart`

**API (from spec):**

```dart
class TpDialogNavEntry {
  const TpDialogNavEntry({
    required this.icon,
    required this.navLabel, // String Function(BuildContext)
    required this.title,
    required this.subtitle,
    required this.bodyBuilder,
  });
  // …
}

class TpDialogNavShell extends StatefulWidget {
  const TpDialogNavShell({
    required this.navTitle,
    required this.entries,
    this.initialIndex = 0,
    this.mobileBreakpoint = 768,
    this.onClose,
    super.key,
  });
}
```

**Narrow:** nested `Navigator` — `/` nav list, `/detail` body; back: detail → list → (caller’s dialog pop). Close on detail calls `onClose ?? Navigator.of(context, rootNavigator: …).pop` for the **dialog** route (use a callback or `Navigator.of(context).popUntil` / store dialog navigator). Spec: X dismisses entire dialog.

**Implementation note:** Prefer an inner `Navigator` with `onGenerateRoute`. For “X closes dialog”, call `onClose` which host sets to `() => Navigator.of(dialogContext).pop()`.

**Wide:** `Row(nav | Expanded(body))` with selected index; no nested push.

- [ ] **Step 1: Write failing tests** (wrap with `showTpDialog(page)` or pump NavShell inside fake fullscreen)

Cover:
- Wide (≥ breakpoint): nav + body both visible; tap changes body.
- Narrow: only nav initially; tap → detail with back; back → nav; X on detail pops outer route.
- `initialIndex: 1` on narrow: opens detail first; back → nav.

Assert **single** app bar row on nav (no PageShell wrapper in test setup).

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client/packages/shared_ui && flutter test test/components/tp_dialog_nav_shell_test.dart`

- [ ] **Step 3: Implement NavShell + export**

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/shared_ui/lib/src/components/dialog/tp_dialog_nav_shell.dart \
  client/packages/shared_ui/lib/shared_ui.dart \
  client/packages/shared_ui/test/components/tp_dialog_nav_shell_test.dart
git commit -m "feat(shared_ui): add TpDialogNavShell for nav-to-detail dialogs"
```

---

### Task 6: Migrate `showSettingsDialog`

**Files:**
- Modify: `client/lib/widgets/settings/settings_dialog.dart`
- Test: `client/test/widgets/settings/settings_dialog_mobile_nav_test.dart` (create)
- Do **not** change Android hub `config_workspace.dart` GoRouter path.

- [ ] **Step 1: Write failing host test**

Pump narrow viewport; open `showSettingsDialog` with 2 stub entries; expect nav labels; tap → detail title; back → nav. Wide: both panes visible.

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client && flutter test test/widgets/settings/settings_dialog_mobile_nav_test.dart`

- [ ] **Step 3: Rewrite `_SettingsDialog` / `showSettingsDialog`**

```dart
return showTpDialog<void>(
  context: context,
  presentation: TpDialogPresentation.page,
  mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
  barrierDismissible: false,
  builder: (ctx) => TpDialogNavShell(
    mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
    onClose: () => Navigator.of(ctx).pop(),
    navTitle: (c) => navTitle(c.l10n),
    initialIndex: initialIndex,
    entries: entries
        .map(
          (e) => TpDialogNavEntry(
            icon: e.icon,
            navLabel: (c) => e.navLabel(c.l10n),
            title: (c) => e.title(c.l10n),
            subtitle: (c) => e.subtitle(c.l10n),
            bodyBuilder: e.bodyBuilder,
          ),
        )
        .toList(),
  ),
);
```

Keep `SettingsDialogEntry` public API for call sites. Remove old fixed 1160×960 Row chrome (NavShell owns layout). Preserve deferred pane mounting if still needed via `bodyBuilder` + existing `SettingsDialogPaneHost` inside each body or a thin adapter — prefer keeping `SettingsDialogPaneHost` inside the selected body path without dual-pane Row.

- [ ] **Step 4: Run new + existing settings-related tests — expect PASS**

Also smoke: Android path still uses push (no change) — optional one-liner in existing chrome test.

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/settings/settings_dialog.dart \
  client/test/widgets/settings/
git commit -m "feat(settings): mobile settings dialog uses TpDialogNavShell"
```

---

### Task 7: Appendix A — first-wave page / NavShell Dialogs

Split by chrome ownership:

| Surface | Path | Chrome |
|---------|------|--------|
| Automations list / editor | `automations_dialog.dart`, `automation_editor_dialog.dart` | `TpDialogPageShell` |
| Expert editor | `expert_editor_dialog.dart` | `TpDialogPageShell` |
| New team | `home_workspace_new_team_dialog.dart` | `TpDialogPageShell` |
| **Landing team settings** | `workspace_landing_team_settings_dialog.dart` | **`TpDialogNavShell`** (dual-pane today — same pattern as Task 6) |
| Run configs | `run_configurations_dialog.dart`, `run_config_editor_dialog.dart` | `TpDialogPageShell` |
| Workspace search | `workspace_search_dialog.dart` | `TpDialogPageShell` |
| SSH profile form | `ssh_profile_form_dialog.dart` | `TpDialogPageShell` |
| MCP OAuth connect | `mcp_oauth_connect_dialog.dart` | `TpDialogPageShell` |

**Stay card:** delete confirms, `showTpTextPromptDialog`, host-key prompt.

- [ ] **Step 1: Failing tests**

Automated minimum:
1. AutomationsDialog (or editor) — narrow + page shell full-bleed.
2. `workspace_landing_team_settings_dialog` — narrow nav → detail → back (NavShell), wide dual-pane.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Migrate**

- Simple surfaces: `showTpDialog(page, mobileBreakpoint: 840)` + wrap body in **`TpDialogPageShell`**.
- **Landing team settings only:** `showTpDialog<bool?>(page, …)` + **`TpDialogNavShell`** (adapt section list → `TpDialogNavEntry`; **do not** wrap in PageShell). Keep draft state + Save/Cancel footer in an **outer StatefulWidget** around NavShell (or shared footer below shell), so save still `pop(true)` for `unbound_compose_body`. Reuse Task 6 entry adapter; pass `onClose: () => Navigator.of(dialogContext).pop()`.

- [ ] **Step 4: Run — PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(dialogs): migrate Appendix A dialogs to page / NavShell"
```

---

### Task 8: Docs + verification

**Files:**
- Modify: `client/packages/shared_ui/README.md` (sidebar fraction + page dialog + NavShell + chrome ownership)
- Spec status already Approved — no change required unless links needed

- [ ] **Step 1: Update README sections for TpSidebar width resolution and Dialog presentation**

- [ ] **Step 2: Run full verification**

```bash
cd client/packages/shared_ui && flutter test
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test \
  test/pages/workspace_ide/workspace_ide_shell_smoke_test.dart \
  test/widgets/settings/ \
  test/pages/home_workspace/home_narrow_drawer_test.dart \
  --exclude-tags integration
```

Expected: analyze clean enough for repo policy; listed tests PASS.

Note: left drawer **width ≈ 80%** is covered by shared_ui Task 2 tests (`0.8 * MediaQuery width`); `home_narrow_drawer_test` covers open/close, not pixel width — do not duplicate unless flaky.

- [ ] **Step 3: Commit**

```bash
git add client/packages/shared_ui/README.md
git commit -m "docs(shared_ui): document mobile drawer fraction and page dialogs"
```

---

## Execution notes

- Use TDD order inside each task; do not skip “FAIL then PASS”.
- If `SettingsDialogPaneHost` keep-alive conflicts with NavShell rebuilds, keep pane host keyed by index inside detail body only.
- Right overlay: never introduce right-edge drag in this plan.
- huji consumers of `shared_ui`: set `widthMobileOverride: 288` if they must keep old width until they migrate (note in README).
