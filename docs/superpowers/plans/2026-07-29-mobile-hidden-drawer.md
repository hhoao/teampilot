# Mobile Hidden Drawer (TpSidebar) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On viewports under 840px, TeamPilot left nav becomes a hidden `TpSidebar` drawer (hamburger + edge swipe), covering Home, Workspace left rail, and hub/settings chrome while keeping the existing Apifox sidebar look.

**Architecture:** Port huji’s `TpSidebar*` into teampilot `shared_ui`, then enhance mobile overlay with edge-drag, system-back dismiss, controlled `openMobile`, and `edgeOpenEnabled`. Hosts wrap narrow layouts with `TpSidebarProvider(mobileBreakpoint: 840)`; desktop/wide keeps today’s in-flow rails. Workspace maps `LayoutCubit.sidebarVisible` ↔ `openMobile` and drops the left `PaneOverlayHost` path.

**Tech Stack:** Flutter, `shared_ui` TpTheme, existing `HomeSidebar` / `WorkspaceSidebar` content widgets, `LayoutCubit`, `AndroidShellChrome`, `WorkspacePanePolicy.narrowBreakpointWidth` (840).

**Spec:** `docs/superpowers/specs/2026-07-29-mobile-hidden-drawer-design.md`

**Source of truth for port:** `/home/hhoa/git/hhoa/huji/huji-app/packages/shared_ui/lib/src/components/sidebar/` (+ `tp_sidebar_theme.dart`, existing tests under `test/components/sidebar/`).

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/shared_ui/lib/src/theme/components/tp_sidebar_theme.dart` | Width / color tokens for sidebar |
| `client/packages/shared_ui/lib/src/components/sidebar/*.dart` | Full `TpSidebar*` tree (port from huji) |
| `client/packages/shared_ui/lib/src/theme/tp_theme_data.dart` | Wire `sidebarTheme` into `TpThemeData` |
| `client/packages/shared_ui/lib/shared_ui.dart` | Export sidebar + theme |
| `client/packages/shared_ui/test/components/sidebar/*.dart` | Port + new gesture / controlled-mobile / edge-disable tests |
| `client/lib/pages/home_workspace/home_workspace_page.dart` | Narrow: `TpSidebar` + full-bleed content; wide: TwoPane (**Provider lives in shell**) |
| `client/lib/pages/home_workspace/home_workspace_shell.dart` | Mount `TpSidebarProvider(mobileBreakpoint: 840)` around title bar + body |
| `client/lib/pages/home_workspace/home_workspace_title_bar.dart` | `TpSidebarTrigger` when home tab + `isMobile` |
| `client/lib/pages/home_workspace/home_workspace_sidebar.dart` | Keep content; tighten for drawer padding if needed |
| `client/lib/pages/workspace_ide/workspace_ide_shell.dart` | Narrow left via TpSidebar; right stays `PaneOverlayHost` |
| `client/lib/services/workspace/workspace_pane_policy.dart` | Stop driving `overlayLeft` when left is TpSidebar-owned (or document bridge) |
| `client/lib/router/app_router.dart` (`_settingsChromeShell`) | Android/narrow hub: Trigger + Home nav drawer; detail hides |
| `client/lib/widgets/workspace_drawer.dart` | Delete or thin-wrap; remove dead Material helper |
| `client/test/pages/home_workspace/...` / workspace / router tests | Host narrow-drawer behavior |

**Constant:** always pass `mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth` (840) from teampilot hosts — do not rely on package default 768.

---

### Task 1: Port `TpSidebarTheme` + wire `TpThemeData`

**Files:**
- Create: `client/packages/shared_ui/lib/src/theme/components/tp_sidebar_theme.dart` (copy from huji; adapt imports)
- Modify: `client/packages/shared_ui/lib/src/theme/tp_theme_data.dart`
- Modify: `client/packages/shared_ui/lib/shared_ui.dart` (export theme)

- [ ] **Step 1: Copy theme file from huji**

Copy `huji-app/packages/shared_ui/lib/src/theme/components/tp_sidebar_theme.dart` into teampilot’s matching path. Fix package imports to teampilot `shared_ui` layout (`../../tp_theme.dart` etc. as siblings require).

- [ ] **Step 2: Add `sidebarTheme` to `TpThemeData`**

Mirror huji: field + `fromColorScheme` default via `TpSidebarTheme.defaults()` / from scheme; include in `copyWith` / equality if those exist.

- [ ] **Step 3: Export**

Add `export 'src/theme/components/tp_sidebar_theme.dart';` to `shared_ui.dart`.

- [ ] **Step 4: Smoke analyze**

Run: `cd client/packages/shared_ui && dart analyze lib/src/theme`

Expected: no errors related to sidebar theme.

- [ ] **Step 5: Commit**

```bash
git add client/packages/shared_ui/lib/src/theme/components/tp_sidebar_theme.dart \
  client/packages/shared_ui/lib/src/theme/tp_theme_data.dart \
  client/packages/shared_ui/lib/shared_ui.dart
git commit -m "$(cat <<'EOF'
feat(shared_ui): add TpSidebarTheme tokens

EOF
)"
```

---

### Task 2: Port core `TpSidebar*` widgets + existing huji tests

**Files:**
- Create: all of `client/packages/shared_ui/lib/src/components/sidebar/` from huji (13 files)
- Create: `client/packages/shared_ui/test/components/sidebar/tp_sidebar_test.dart`, `tp_sidebar_provider_test.dart`, `tp_sidebar_menu_test.dart`, `tp_sidebar_rail_trigger_test.dart` (port)
- Modify: `client/packages/shared_ui/lib/shared_ui.dart` exports

- [ ] **Step 1: Copy sidebar component tree**

Copy the huji `lib/src/components/sidebar/` directory verbatim into teampilot `shared_ui`, fixing relative imports only.

- [ ] **Step 2: Export public API**

Export at least: `tp_sidebar.dart`, `tp_sidebar_provider.dart`, `tp_sidebar_scope.dart`, `tp_sidebar_trigger.dart`, `tp_sidebar_inset.dart`, `tp_sidebar_rail.dart`, header/content/footer/group/menu/config as huji does (check huji `shared_ui.dart` export list and match).

- [ ] **Step 3: Port tests**

Copy the four huji sidebar test files; ensure `_wrap` helpers use teampilot `TpTheme` / `TpThemeData.fromColorScheme`.

- [ ] **Step 4: Run ported tests — expect PASS**

Run: `cd client/packages/shared_ui && flutter test test/components/sidebar/`

Expected: PASS (baseline port).

- [ ] **Step 5: Commit**

```bash
git add client/packages/shared_ui/lib/src/components/sidebar \
  client/packages/shared_ui/test/components/sidebar \
  client/packages/shared_ui/lib/shared_ui.dart
git commit -m "$(cat <<'EOF'
feat(shared_ui): port TpSidebar composition tree from huji

EOF
)"
```

---

### Task 3: Controlled `openMobile` + `edgeOpenEnabled`

**Files:**
- Modify: `tp_sidebar_provider.dart`, `tp_sidebar_scope.dart`, `tp_sidebar.dart`
- Test: `test/components/sidebar/tp_sidebar_provider_test.dart` (extend) and/or new `tp_sidebar_mobile_controls_test.dart`

Needed so Workspace can bridge `LayoutCubit.sidebarVisible` and hub detail can disable edge-open.

- [ ] **Step 1: Write failing tests**

```dart
testWidgets('controlled openMobile follows parent value', (tester) async {
  var openMobile = false;
  late StateSetter setParent;

  await tester.pumpWidget(
    StatefulBuilder(
      builder: (context, setState) {
        setParent = setState;
        return _wrapMobile(
          openMobile: openMobile,
          onOpenMobileChange: (v) => setState(() => openMobile = v),
          child: const TpSidebar(child: Text('drawer-body')),
        );
      },
    ),
  );
  expect(find.text('drawer-body'), findsNothing);

  setParent(() => openMobile = true);
  await tester.pumpAndSettle();
  expect(find.text('drawer-body'), findsOneWidget);
});

testWidgets('edgeOpenEnabled is exposed on scope', (tester) async {
  await tester.pumpWidget(
    _wrapMobile(
      edgeOpenEnabled: false,
      child: const TpSidebar(child: Text('drawer-body')),
      content: Builder(
        builder: (context) {
          expect(TpSidebarScope.of(context).edgeOpenEnabled, isFalse);
          return const SizedBox();
        },
      ),
    ),
  );
});
```

Use `_wrapMobile` with `Size(400, 800)` and `TpSidebarProvider(mobileBreakpoint: 840, ...)`. When porting huji tests in Task 2, keep their default 768; for teampilot host-facing tests always use **840**.

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client/packages/shared_ui && flutter test test/components/sidebar/tp_sidebar_mobile_controls_test.dart`

Expected: FAIL — missing `openMobile` / `edgeOpenEnabled` API.

- [ ] **Step 3: Implement API**

On `TpSidebarProvider`:
- `bool? openMobile`, `ValueChanged<bool>? onOpenMobileChange` (controlled pattern like `open`)
- `bool edgeOpenEnabled = true`

On `TpSidebarScope`: expose `edgeOpenEnabled`.

`setOpenMobile` / `_setOpenMobile`: if controlled, call `onOpenMobileChange`; else local state.

- [ ] **Step 4: Run — expect PASS** (controlled open; edge flag). Gesture ignore covered in Task 4 if drag not yet implemented.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(shared_ui): controlled openMobile and edgeOpenEnabled

EOF
)"
```

---

### Task 4: Mobile edge-drag + system back dismiss

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/sidebar/tp_sidebar.dart` (and optionally extract `tp_sidebar_mobile_drawer.dart` if file exceeds ~400 lines)
- Test: `client/packages/shared_ui/test/components/sidebar/tp_sidebar_edge_drag_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
testWidgets('drag from left edge past midpoint opens drawer', (tester) async {
  await tester.pumpWidget(_wrapMobile(
    child: const TpSidebar(child: Text('drawer-body')),
  ));
  final gesture = await tester.startGesture(const Offset(2, 400));
  await gesture.moveBy(const Offset(200, 0));
  await gesture.up();
  await tester.pumpAndSettle();
  expect(find.text('drawer-body'), findsOneWidget);
});

testWidgets('drag below midpoint snaps closed', (tester) async {
  await tester.pumpWidget(_wrapMobile(
    child: const TpSidebar(child: Text('drawer-body')),
    content: Builder(
      builder: (context) => TextButton(
        onPressed: () => TpSidebarScope.of(context).setOpenMobile(true),
        child: const Text('open-drawer'),
      ),
    ),
  ));
  await tester.tap(find.text('open-drawer'));
  await tester.pumpAndSettle();
  expect(find.text('drawer-body'), findsOneWidget);

  // Drag drawer left by less than half of widthMobile (~288 → move ~80).
  final panel = tester.getRect(find.text('drawer-body'));
  final gesture = await tester.startGesture(panel.center);
  await gesture.moveBy(const Offset(-80, 0));
  await gesture.up();
  await tester.pumpAndSettle();
  expect(find.text('drawer-body'), findsNothing);
});

testWidgets('system back closes open drawer without claiming route pop',
    (tester) async {
  await tester.pumpWidget(_wrapMobile(
    child: const TpSidebar(child: Text('drawer-body')),
    content: Builder(
      builder: (context) => TextButton(
        onPressed: () => TpSidebarScope.of(context).setOpenMobile(true),
        child: const Text('open-drawer'),
      ),
    ),
  ));
  await tester.tap(find.text('open-drawer'));
  await tester.pumpAndSettle();
  expect(find.text('drawer-body'), findsOneWidget);

  final handled = await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(find.text('drawer-body'), findsNothing);
  // Drawer PopScope should consume the pop; exact `handled` depends on
  // Flutter version — assert drawer closed and no exception.
  expect(tester.takeException(), isNull);
  expect(handled, isA<bool>());
});

testWidgets('edge drag does nothing when edgeOpenEnabled is false', (tester) async {
  await tester.pumpWidget(_wrapMobile(
    edgeOpenEnabled: false,
    child: const TpSidebar(child: Text('drawer-body')),
  ));
  final gesture = await tester.startGesture(const Offset(2, 400));
  await gesture.moveBy(const Offset(200, 0));
  await gesture.up();
  await tester.pumpAndSettle();
  expect(find.text('drawer-body'), findsNothing);
});
```

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client/packages/shared_ui && flutter test test/components/sidebar/tp_sidebar_edge_drag_test.dart`

- [ ] **Step 3: Implement**

In mobile overlay path of `TpSidebar`:
1. Keep scrim + sliding panel (`AnimationController` or drag-driven offset).
2. When closed and `edgeOpenEnabled`: listen for horizontal drags starting within ~20px of the left (or right if `side == right`) edge of the **host** overlay/fullscreen area.
3. Follow finger; on release, if progress > 0.5 (or velocity high) → `setOpenMobile(true)`, else close.
4. Wrap open drawer with `PopScope(canPop: false, onPopInvokedWithResult: ...)` → `setOpenMobile(false)` when open.
5. Scrim tap → close (already present in huji; keep). Add a widget test that taps the barrier/`ModalBarrier` and expects drawer closed if not already covered by ported tests.

- [ ] **Step 4: Run all sidebar tests — expect PASS**

Run: `cd client/packages/shared_ui && flutter test test/components/sidebar/`

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(shared_ui): edge-drag and back-dismiss for TpSidebar mobile drawer

EOF
)"
```

---

### Task 5: Home narrow shell — hidden drawer

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_shell.dart` — **mount `TpSidebarProvider` here** (wraps title bar + body)
- Modify: `client/lib/pages/home_workspace/home_workspace_title_bar.dart` — show `TpSidebarTrigger` when `TpSidebarScope.isMobile` **and** home tab is active (`activeTab == null` / no workspace tab) — do not show Home Trigger on workspace tabs (those use Workspace sidebar toggle)
- Modify: `client/lib/pages/home_workspace/home_workspace_page.dart` — narrow: `TpSidebar` + full-bleed right pane; wide: keep `TwoPaneSplitView` (**no Provider inside HomePage**)
- Modify: `client/lib/pages/home_workspace/home_workspace_sidebar.dart` if drawer padding needs a denser path
- Optionally add: `AppKeys.homeSidebarTrigger` in `client/lib/utils/ui/app_keys.dart` (or use `find.byType(TpSidebarTrigger)`)
- Test: `client/test/pages/home_workspace/home_narrow_drawer_test.dart` (new)

**Provider placement (required):**

```
HomeShell.build
  └─ TpSidebarProvider(mobileBreakpoint: 840)
       └─ Scaffold
            └─ Column
                 ├─ _HomeShellTitleBar  ← may contain TpSidebarTrigger
                 └─ Expanded(HomeWorkspaceBodyStack → HomePage)
                      └─ HomePage: TpSidebar + content (narrow) OR TwoPane (wide)
```

Do **not** put `TpSidebarProvider` only inside `HomePage` — the title-bar Trigger would be outside the scope.

- [ ] **Step 1: Write failing widget test**

Pump Home shell/page harness at `Size(400, 800)` with Provider at shell level:
- Expect: no permanent sidebar column; HomeSidebar labels not visible until open.
- Tap `find.byType(TpSidebarTrigger)` (or `AppKeys.homeSidebarTrigger` if added) → see automations / favorites labels.
- Tap a nav row → drawer closes.

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client && flutter test test/pages/home_workspace/home_narrow_drawer_test.dart`

- [ ] **Step 3: Implement Home wiring**

1. Wrap `HomeShell` scaffold subtree with `TpSidebarProvider(mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth)`.
2. In title bar: if `TpSidebarScope.maybeOf(context)?.isMobile == true` **and** current location is home (no active workspace tab), show `TpSidebarTrigger`.
3. In `HomePage` narrow branch:

```dart
Row(
  children: [
    TpSidebar(
      collapsible: TpSidebarCollapsible.offcanvas,
      child: HomeSidebar(
        ...
        onSelectGlobalView: (view) {
          /* existing setState */
          TpSidebarScope.maybeOf(context)?.setOpenMobile(false);
        },
        // same close for library / all-workspaces callbacks
      ),
    ),
    Expanded(child: /* right pane */),
  ],
);
```

Wide path: keep existing `TwoPaneSplitView` (sidebar in-flow; Trigger hidden because `!isMobile`).

- [ ] **Step 4: Run test — expect PASS**

Also: `cd client && flutter test test/pages/home_workspace/ --exclude-tags integration` if a home suite exists.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(home): narrow viewport uses TpSidebar hidden drawer

EOF
)"
```

---

### Task 6: Workspace narrow left → TpSidebar; keep right overlay

**Files:**
- Modify: `client/lib/pages/workspace_ide/workspace_ide_shell.dart`
- Modify: `client/lib/services/workspace/workspace_pane_policy.dart` — narrow: `overlayLeft: false` (left owned by TpSidebar); keep `overlayRight` as today
- Modify: `client/lib/pages/workspace_shell/workspace_shell_tabs.dart` if sidebar toggle should keep using `setSidebarVisible` (bridged to `openMobile`)
- Update tests:
  - `client/test/pages/workspace_ide/workspace_ide_shell_smoke_test.dart` (or whatever the smoke file is named) — narrow + `sidebarVisible: true` must **not** show left content until drawer open / after Trigger
  - `client/test/services/workspace/workspace_pane_policy_test.dart` — assert narrow `overlayLeft == false`
  - New / extended: edge drag or Trigger → `layout.state.preferences.sidebarVisible == true`; dismiss → `false`

- [ ] **Step 1: Write / update failing tests**

At width 400:
1. First paint with default prefs (`sidebarVisible: true` from desktop history) still shows **closed** drawer / full-width center — left list not visible until user opens.
2. Trigger or edge drag opens left content and write-through sets `sidebarVisible == true`.
3. Scrim dismiss → `sidebarVisible == false` and drawer closed.
4. Right overlay still works independently.
5. Update existing smoke/policy tests that assumed `overlayLeft` shows left immediately.

- [ ] **Step 2: Run — expect FAIL** (new assertions + broken old smoke)

- [ ] **Step 3: Implement**

**Narrow `openMobile` rule (do not bind raw `prefs.sidebarVisible` as initial open):**

Desktop prefs often default `sidebarVisible: true` (docked rail). On narrow, that must **not** mean “drawer starts open”. Spec: main content full-bleed until the user opens the drawer.

Use one of these equivalent strategies (pick one and stick to it in tests):

**A (recommended):** Uncontrolled `openMobile` for narrow entry — start `false`. On open/close via Trigger / edge / scrim / toggle, call `layout.setSidebarVisible(v)` so prefs stay aligned for the next session’s *intent*, but **when crossing into narrow**, force drawer closed once (`setOpenMobile(false)` / ignore stale true until user acts). Wide mode continues to use `sidebarVisible` for docked pane.

**B:** Controlled bridge, but when `isMobile` becomes true, if you would sync from prefs, coerce initial `openMobile` to `false` and optionally `setSidebarVisible(false)` so controlled value matches.

Concrete wiring sketch (strategy A):

```dart
TpSidebarProvider(
  mobileBreakpoint: 840,
  // do NOT pass openMobile: prefs.sidebarVisible on narrow
  onOpenMobileChange: (v) => layout.setSidebarVisible(v),
  child: ...
);
// Shell toggle on narrow: setSidebarVisible + setOpenMobile via scope.toggleSidebar
```

Also:
1. On narrow: render `TpSidebar(child: left)` + center; **`PaneOverlayHost(left: null, showLeft: false)`**; right overlay unchanged.
2. On wide: keep docked MultiPane left; `sidebarVisible` drives dock as today.
3. Shell sidebar toggle on narrow: `toggleSidebar()` / `setOpenMobile` + write prefs.

- [ ] **Step 4: Run workspace-related tests — expect PASS**

Run: `cd client && flutter test test/pages/workspace_ide/ test/services/workspace/` (adjust globs to actual paths).

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(workspace): narrow left rail uses TpSidebar drawer

EOF
)"
```

---

### Task 7: Hub / settings chrome drawer + `shouldHideDrawer`

**Files:**
- Modify: `client/lib/router/app_router.dart` (`_settingsChromeShell`)
- Possibly extract: `client/lib/widgets/android_hub_nav_drawer.dart` or reuse `HomeSidebar` with callbacks that `context.go(...)` + `setOpenMobile(false)`
- Modify: ensure `AndroidShellChrome.shouldHideDrawer` gates Trigger + `edgeOpenEnabled: false`
- Test: `client/test/router/android_settings_chrome_drawer_test.dart` (new)

- [ ] **Step 1: Write failing test**

- Android (or width &lt; 840) settings root: finds Trigger; open drawer; finds Home global nav labels (automations / skills / …).
- Detail path (`/config/layout`): no Trigger; `edgeOpenEnabled` false / drawer not openable; back button present.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement `_settingsChromeShell`**

```dart
if (Platform.isAndroid || width < 840) {
  final hide = AndroidShellChrome.shouldHideDrawer(path);
  return TpSidebarProvider(
    mobileBreakpoint: 840,
    edgeOpenEnabled: !hide,
    child: Scaffold(
      appBar: AppBar(
        leading: hide
            ? BackButton(...)
            : const TpSidebarTrigger(),
        ...
      ),
      body: Row(
        children: [
          TpSidebar(child: /* HomeSidebar or shared global nav */),
          Expanded(child: child),
        ],
      ),
    ),
  );
}
```

Nav presses: `go` / `push` then close drawer. Prefer **reusing HomeSidebar** entry callbacks mapped to routes / `HomeGlobalView` deep links — do not invent a second menu taxonomy.

- [ ] **Step 4: Run test — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(android): hub settings chrome uses Home nav drawer

EOF
)"
```

---

### Task 8: Remove dead `WorkspaceDrawer` + README + analyze

**Files:**
- Delete or replace: `client/lib/widgets/workspace_drawer.dart`
- Grep for `WorkspaceDrawer` usages — should be none; remove imports
- Update: `client/packages/shared_ui/README.md` sidebar section (port from huji README blurb if missing)
- Test: full analyze + targeted tests

- [ ] **Step 1: Grep and delete**

```bash
rg 'WorkspaceDrawer' client/
```

Remove file and any stale references.

- [ ] **Step 2: Document in shared_ui README**

Short section: Provider + mobile drawer + teampilot `mobileBreakpoint: 840` note.

- [ ] **Step 3: Verify**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd packages/shared_ui && flutter test test/components/sidebar/
cd ../.. && flutter test \
  test/pages/home_workspace/home_narrow_drawer_test.dart \
  test/router/android_settings_chrome_drawer_test.dart \
  test/pages/workspace_ide/ \
  test/services/workspace/
```

Expected: clean analyze; tests PASS. (Adjust globs if some paths differ; do not skip workspace IDE after Task 6.)

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
chore: drop unused WorkspaceDrawer; document TpSidebar mobile

EOF
)"
```

---

## Success checklist (manual)

- [ ] Phone emulator Home: full-width content; hamburger opens Apifox-looking nav; edge swipe works; nav closes drawer
- [ ] Workspace narrow: left sessions in drawer; right tools still overlay; left edge does not open right tools
- [ ] Hub root drawer = Home nav; hub detail = back, no edge open
- [ ] Desktop / width ≥ 840: permanent sidebars unchanged

---

## Notes for implementers

- Prefer **copy-then-adapt** from huji for Tasks 1–2; do not re-design the API.
- Never hard-code 768 in teampilot hosts — use `WorkspacePanePolicy.narrowBreakpointWidth`.
- Package stays router-agnostic; hosts close drawer after navigation.
- If `tp_sidebar.dart` grows past ~400 lines after gestures, extract `tp_sidebar_mobile_drawer.dart` in the same task rather than deferring.
