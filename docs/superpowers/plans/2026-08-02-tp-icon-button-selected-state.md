# TpIconButton Selected State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `TpIconButton.selected` chrome matching `_HomePill`, and wire mobile title-bar hamburgers plus the desktop sidebar visibility toggle so open state is visually obvious (`menu` → `menu_open` on hamburgers).

**Architecture:** Extend `TpIconButton` in `shared_ui` with a `selected` flag (per-property color/fill overrides; border always when selected). `TpSidebarTrigger` gains `selected` and uses `icon:` `IconData` for the default menu glyphs so tint applies. Title-bar and workspace shell call sites pass open-state signals already available (`openMobile`, `mobileWorkspaceDrawerOpen`, `effectiveOpen`).

**Tech Stack:** Flutter, `flutter_bloc`, `shared_ui` (`TpIconButton`, `TpSidebarTrigger`, `TpSidebarScope`).

**Spec:** `docs/superpowers/specs/2026-08-02-tp-icon-button-selected-state-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/shared_ui/lib/src/components/icon_button/tp_icon_button.dart` | Add `selected`; resolve fill/border/icon color |
| `client/packages/shared_ui/lib/src/components/sidebar/tp_sidebar_trigger.dart` | Pass `selected`; default icons via `IconData` |
| `client/packages/shared_ui/test/components/tp_icon_button_test.dart` | Selected chrome + override tests |
| `client/packages/shared_ui/test/components/sidebar/tp_sidebar_rail_trigger_test.dart` | Keep trigger tap tests green |
| `client/lib/pages/home_workspace/home_workspace_title_bar.dart` | Wire hamburger selected + `menu_open` |
| `client/lib/pages/workspace_shell/workspace_shell_tabs.dart` | Sidebar toggle uses `selected` |
| `client/test/pages/home_workspace/home_workspace_title_bar_test.dart` | Assert selected + `menu_open` when open |
| `client/test/pages/workspace_shell/workspace_shell_sidebar_toggle_test.dart` | Assert `selected` instead of hand `color` |

**Note:** `client/packages/shared_ui` is a git submodule — commit shared_ui changes inside that repo, then update the parent pointer.

---

### Task 1: `TpIconButton.selected` chrome (TDD)

**Files:**
- Modify: `client/packages/shared_ui/test/components/tp_icon_button_test.dart`
- Modify: `client/packages/shared_ui/lib/src/components/icon_button/tp_icon_button.dart`

- [ ] **Step 1: Write failing selected-chrome tests**

Append to `tp_icon_button_test.dart`:

```dart
testWidgets('TpIconButton selected applies pill-matched chrome', (tester) async {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.orange);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: TpTheme(
        data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
        child: Scaffold(
          body: TpIconButton(
            icon: Icons.menu,
            selected: true,
            onTap: () {},
          ),
        ),
      ),
    ),
  );

  final button = tester.widget<TpIconButton>(find.byType(TpIconButton));
  expect(button.selected, isTrue);

  final ink = tester.widget<Ink>(find.descendant(
    of: find.byType(TpIconButton),
    matching: find.byType(Ink),
  ));
  final decoration = ink.decoration! as BoxDecoration;
  expect(decoration.color, scheme.primary.withValues(alpha: 0.16));
  expect(decoration.border?.top.color, scheme.primary.withValues(alpha: 0.28));

  final icon = tester.widget<Icon>(find.byIcon(Icons.menu));
  expect(icon.color, scheme.primary);
});

testWidgets('TpIconButton selected respects explicit color and backgroundColor', (
  tester,
) async {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.orange);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: TpTheme(
        data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
        child: Scaffold(
          body: TpIconButton(
            icon: Icons.menu,
            selected: true,
            color: Colors.red,
            backgroundColor: Colors.transparent,
            onTap: () {},
          ),
        ),
      ),
    ),
  );

  final ink = tester.widget<Ink>(find.descendant(
    of: find.byType(TpIconButton),
    matching: find.byType(Ink),
  ));
  final decoration = ink.decoration! as BoxDecoration;
  expect(decoration.color, Colors.transparent);
  // Border still applies when selected.
  expect(decoration.border?.top.color, scheme.primary.withValues(alpha: 0.28));
  expect(tester.widget<Icon>(find.byIcon(Icons.menu)).color, Colors.red);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd client/packages/shared_ui && flutter test test/components/tp_icon_button_test.dart
```

Expected: FAIL — `selected` not defined / decoration has no border / wrong colors.

- [ ] **Step 3: Implement `selected` on `TpIconButton`**

In `tp_icon_button.dart`:

1. Add `this.selected = false` to the constructor and `final bool selected;`.
2. Resolve colors per spec:

```dart
final Color effectiveColor;
if (!enabled) {
  effectiveColor = cs.onSurface.withValues(alpha: 0.38);
} else if (color != null) {
  effectiveColor = color!;
} else if (selected) {
  effectiveColor = cs.primary;
} else {
  effectiveColor = cs.onSurface;
}

final Color? fill = backgroundColor ??
    (selected ? cs.primary.withValues(alpha: 0.16) : null);

final Border? border = selected
    ? Border.all(color: cs.primary.withValues(alpha: 0.28))
    : null;
```

3. Update `BoxDecoration`:

```dart
decoration: BoxDecoration(
  borderRadius: radius,
  color: fill,
  border: border,
),
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd client/packages/shared_ui && flutter test test/components/tp_icon_button_test.dart
```

Expected: PASS

- [ ] **Step 5: Commit in shared_ui submodule**

```bash
cd client/packages/shared_ui
git add lib/src/components/icon_button/tp_icon_button.dart test/components/tp_icon_button_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): add TpIconButton selected chrome

EOF
)"
```

---

### Task 2: `TpSidebarTrigger` selected + IconData default glyphs

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/sidebar/tp_sidebar_trigger.dart`
- Modify: `client/packages/shared_ui/test/components/sidebar/tp_sidebar_rail_trigger_test.dart` (only if needed)

- [ ] **Step 1: Write failing test for selected icon swap**

Add to `tp_sidebar_rail_trigger_test.dart` (or `tp_icon_button_test.dart` if preferred):

```dart
testWidgets('TpSidebarTrigger selected uses menu_open and selected chrome', (
  tester,
) async {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: MaterialApp(
        theme: ThemeData(colorScheme: scheme, useMaterial3: true),
        home: TpTheme(
          data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
          child: TpSidebarProvider(
            defaultOpen: false,
            child: const Scaffold(
              body: TpSidebarTrigger(selected: true),
            ),
          ),
        ),
      ),
    ),
  );

  expect(find.byIcon(Icons.menu_open), findsOneWidget);
  final button = tester.widget<TpIconButton>(find.byType(TpIconButton));
  expect(button.selected, isTrue);
  expect(button.icon, Icons.menu_open);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd client/packages/shared_ui && flutter test test/components/sidebar/tp_sidebar_rail_trigger_test.dart
```

Expected: FAIL — no `selected` param / still `Icons.menu` via `iconWidget`.

- [ ] **Step 3: Implement trigger wiring**

Replace `tp_sidebar_trigger.dart` build path:

```dart
class TpSidebarTrigger extends StatelessWidget {
  const TpSidebarTrigger({
    super.key,
    this.icon,
    this.tooltip,
    this.size = TpIconButton.kDefaultSize,
    this.selected = false,
  });

  final Widget? icon;
  final String? tooltip;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (icon != null) {
      return TpIconButton(
        iconWidget: icon,
        onTap: TpSidebarScope.of(context).toggleSidebar,
        tooltip: tooltip,
        size: size,
        selected: selected,
      );
    }
    return TpIconButton(
      icon: selected ? Icons.menu_open : Icons.menu,
      onTap: TpSidebarScope.of(context).toggleSidebar,
      tooltip: tooltip,
      size: size,
      selected: selected,
    );
  }
}
```

- [ ] **Step 4: Run sidebar trigger tests**

Run:

```bash
cd client/packages/shared_ui && flutter test test/components/sidebar/tp_sidebar_rail_trigger_test.dart
```

Expected: PASS (existing tap tests + new selected test).

- [ ] **Step 5: Commit in shared_ui submodule**

```bash
cd client/packages/shared_ui
git add lib/src/components/sidebar/tp_sidebar_trigger.dart test/components/sidebar/tp_sidebar_rail_trigger_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): TpSidebarTrigger selected uses menu_open

EOF
)"
```

---

### Task 3: Wire title-bar mobile hamburger

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_title_bar.dart` (`_HomeTitleBarMobileDrawerTrigger`)
- Modify: `client/test/pages/home_workspace/home_workspace_title_bar_test.dart`

- [ ] **Step 1: Write failing title-bar selected tests**

Add tests that open the drawer/sidebar then assert:

```dart
testWidgets('mobile workspace hamburger shows selected menu_open when drawer open', (
  tester,
) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final theme = ThemeData(useMaterial3: true);
  late LayoutCubit layout;
  await tester.pumpWidget(
    TpTheme(
      data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
      child: _wrapTitleBar(
        chatCubit: chatCubit,
        child: Builder(
          builder: (context) {
            layout = context.read<LayoutCubit>();
            return TpSidebarProvider(
              mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
              child: MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: theme,
                home: const Scaffold(
                  body: HomeTitleBar(
                    tabs: [HomeWorkspaceTab(id: 'ws-a', name: 'Solo')],
                    activeTabKey: 'ws-a',
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  layout.openMobileWorkspaceDrawer();
  await tester.pumpAndSettle();

  expect(find.byIcon(Icons.menu_open), findsOneWidget);
  final button = tester.widget<TpIconButton>(
    find.ancestor(
      of: find.byIcon(Icons.menu_open),
      matching: find.byType(TpIconButton),
    ),
  );
  expect(button.selected, isTrue);
});
```

Also add a home-path variant (`activeTabKey: null`) with equal detail. Suggested shape (mirror `home_narrow_drawer_test.dart` harness: phone size, `TpSidebarProvider` + narrow breakpoint, empty or home tabs):

```dart
testWidgets('mobile home hamburger shows selected menu_open when sidebar open', (
  tester,
) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final theme = ThemeData(useMaterial3: true);
  await tester.pumpWidget(
    TpTheme(
      data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
      child: _wrapTitleBar(
        chatCubit: chatCubit,
        child: TpSidebarProvider(
          mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: theme,
            home: const Scaffold(
              body: HomeTitleBar(
                tabs: [HomeWorkspaceTab(id: 'ws-a', name: 'Solo')],
                activeTabKey: null,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Open via scope (or tap the menu icon once).
  final scope = tester.element(find.byType(HomeTitleBar));
  TpSidebarScope.of(scope).setOpenMobile(true);
  await tester.pumpAndSettle();

  expect(find.byIcon(Icons.menu_open), findsOneWidget);
  final button = tester.widget<TpIconButton>(
    find.ancestor(
      of: find.byIcon(Icons.menu_open),
      matching: find.byType(TpIconButton),
    ),
  );
  expect(button.selected, isTrue);
});
```

Do **not** ship Task 3 with only the workspace assertion — spec requires both paths.

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd client && flutter test test/pages/home_workspace/home_workspace_title_bar_test.dart --name "hamburger"
```

Expected: FAIL — still `Icons.menu` / `selected: false` while drawer open.

- [ ] **Step 3: Implement `_HomeTitleBarMobileDrawerTrigger`**

Replace the class body roughly with:

```dart
@override
Widget build(BuildContext context) {
  if (activeTabKey == null) {
    final openMobile = TpSidebarScope.of(context).openMobile;
    return TpSidebarTrigger(
      size: TpIconButton.kMobileTapSize,
      selected: openMobile,
    );
  }

  final composeLanding = context.select<ChatCubit, bool>(
    (c) => c.state.newChatActive,
  );
  return BlocBuilder<LayoutCubit, LayoutState>(
    buildWhen: (a, b) =>
        a.preferences.sidebarVisible != b.preferences.sidebarVisible ||
        a.narrowLeftSuppressed != b.narrowLeftSuppressed ||
        a.preferences.rightToolsVisible != b.preferences.rightToolsVisible ||
        a.landingRightToolsOverride != b.landingRightToolsOverride,
    builder: (context, layoutState) {
      final open = mobileWorkspaceDrawerOpen(
        layoutState: layoutState,
        composeLanding: composeLanding,
      );
      return TpIconButton(
        icon: open ? Icons.menu_open : Icons.menu,
        size: TpIconButton.kMobileTapSize,
        selected: open,
        onTap: () {
          final layout = context.read<LayoutCubit>();
          if (open) {
            layout.closeMobileWorkspaceDrawer(composeLanding: composeLanding);
          } else {
            layout.openMobileWorkspaceDrawer(composeLanding: composeLanding);
          }
        },
      );
    },
  );
}
```

- [ ] **Step 4: Run title-bar tests**

Run:

```bash
cd client && flutter test test/pages/home_workspace/home_workspace_title_bar_test.dart
```

Expected: PASS

- [ ] **Step 5: Commit app changes (+ submodule pointer if shared_ui advanced)**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/packages/shared_ui
git add client/lib/pages/home_workspace/home_workspace_title_bar.dart
git add client/test/pages/home_workspace/home_workspace_title_bar_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): show selected menu_open on mobile drawer hamburger

EOF
)"
```

---

### Task 4: Desktop sidebar visibility toggle uses `selected`

**Files:**
- Modify: `client/lib/pages/workspace_shell/workspace_shell_tabs.dart` (`WorkspaceShellSidebarVisibilityToggle` only)
- Modify: `client/test/pages/workspace_shell/workspace_shell_sidebar_toggle_test.dart`

- [ ] **Step 1: Update failing assertions for `selected`**

In `workspace_shell_sidebar_toggle_test.dart`, change closed/open expectations:

```dart
// after pump with narrowLeftSuppressed (effective closed):
expect(button.selected, isFalse);

// after tap clears suppression (effective open):
expect(buttonAfterClear.selected, isTrue);

// remove expects on button.color / buttonAfterClear.color
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd client && flutter test test/pages/workspace_shell/workspace_shell_sidebar_toggle_test.dart
```

Expected: FAIL — `selected` still false / field unused while open (if still using `color:` only).

- [ ] **Step 3: Wire `selected` on the toggle**

In `WorkspaceShellSidebarVisibilityToggle`, replace color/background wiring:

```dart
return TpIconButton(
  key: AppKeys.sidebarVisibilityButton,
  icon: Icons.view_sidebar_outlined,
  tooltip: effectiveOpen
      ? l10n.sidebarPanelHidden
      : l10n.sidebarPanelVisible,
  selected: effectiveOpen,
  onTap: () {
    final layout = context.read<LayoutCubit>();
    if (effectiveOpen) {
      layout.setSidebarVisible(false);
      layout.clearNarrowLeftSuppressed();
    } else {
      layout.clearNarrowLeftSuppressed();
      layout.setSidebarVisible(true);
    }
  },
);
```

Remove unused `cs` if it becomes unused. **Do not change** `WorkspaceShellRightToolsVisibilityToggle`.

- [ ] **Step 4: Run toggle + related tests**

Run:

```bash
cd client && flutter test test/pages/workspace_shell/workspace_shell_sidebar_toggle_test.dart test/pages/home_workspace/home_workspace_title_bar_test.dart
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/pages/workspace_shell/workspace_shell_tabs.dart
git add client/test/pages/workspace_shell/workspace_shell_sidebar_toggle_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): sidebar visibility toggle uses TpIconButton.selected

EOF
)"
```

---

### Task 5: Verification sweep

- [ ] **Step 1: Run focused package + app suites**

```bash
cd client/packages/shared_ui && flutter test test/components/tp_icon_button_test.dart test/components/sidebar/tp_sidebar_rail_trigger_test.dart
cd /home/hhoa/git/hhoa/teampilot/client && flutter test \
  test/pages/home_workspace/home_workspace_title_bar_test.dart \
  test/pages/workspace_shell/workspace_shell_sidebar_toggle_test.dart
```

Expected: all PASS

- [ ] **Step 2: Manual smoke (optional)**

On a phone-width viewport: open/close home sidebar and workspace drawer — hamburger should show pill chrome + `menu_open` while open. On desktop: left sidebar toggle should show the same selected fill/border when the sidebar is effectively open.
