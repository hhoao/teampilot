# Narrow Section Top Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On narrow viewports, show Skills / Plugins / MCP / Extensions and workspace-manage section options as underline top tabs (team-settings style) instead of dropping left nav.

**Architecture:** Opt-in `compactSectionTabs` + `items` on `WorkspaceAdaptiveSectionPage`. Wide keeps split nav; narrow renders `HomeContentTabBar` above body. In-scope library roots always redirect to default `installed` section; `AndroidShellChrome` exits the library on back (no Hub bounce). Out-of-scope Adaptive callers unchanged.

**Tech Stack:** Flutter / Dart, `flutter_test`, `go_router`, existing `HomeContentTabBar`, `WorkspacePanePolicy.narrowBreakpointWidth` (840).

**Spec:** `docs/superpowers/specs/2026-08-02-narrow-section-top-tabs-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/widgets/settings/workspace_section_nav_item.dart` | `WorkspaceSectionNavItem` data class |
| `client/lib/widgets/settings/workspace_section_tab_bar.dart` | Re-export / thin wrapper around underline tabs (moved from home) **or** import shared bar |
| `client/lib/pages/home_workspace/home_workspace_content_header.dart` | Keep `HomeContentTabBar` API; implement via shared underline tab bar to avoid style drift |
| `client/lib/widgets/settings/workspace_section_host.dart` | Adaptive branches: wide split / narrow tabs / legacy Android body-only |
| `client/lib/widgets/settings/workspace_section_compact_shell.dart` | Narrow shell: header + tabs + divider + body (optional split if host grows) |
| `client/lib/pages/skills/skill_management_page.dart` | Opt-in `items` + `compactSectionTabs` |
| `client/lib/pages/plugins/plugin_management_page.dart` | Same |
| `client/lib/pages/mcp/mcp_management_page.dart` | Same (not `McpFormNavPage`) |
| `client/lib/pages/extensions/extension_management_page.dart` | Same (single section → no strip) |
| `client/lib/pages/home_workspace/workspace/workspace_config_workspace.dart` | Manage panel opt-in |
| `client/lib/router/app_router.dart` | Always redirect library roots → `/…/installed` (drop Android Hub exception) |
| `client/lib/router/android_shell_chrome.dart` | Library back exits to pop or `/home-v2`; cover plugins/extensions |
| `client/test/widgets/settings/workspace_section_host_test.dart` | Adaptive compact-tabs coverage |
| `client/test/router/android_shell_chrome_test.dart` | Create or extend back/exit tests if file exists; else add focused test |

**Delete when unused after router change:** `*ManagementHubPage` widgets (Skills/Plugins/MCP/Extensions) if nothing else references them; update hub widget tests accordingly.

---

### Task 1: Shared underline tab bar + `WorkspaceSectionNavItem`

**Files:**
- Create: `client/lib/widgets/settings/workspace_section_nav_item.dart`
- Create: `client/lib/widgets/settings/workspace_section_tab_bar.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_content_header.dart`
- Test: `client/test/widgets/settings/workspace_section_tab_bar_test.dart`

- [ ] **Step 1: Write failing tab-bar test**

```dart
testWidgets('section tab bar selects and invokes onSelect', (tester) async {
  var selected = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WorkspaceSectionTabBar(
          tabs: const ['Alpha', 'Beta'],
          selectedIndex: selected,
          onSelect: (i) => selected = i,
        ),
      ),
    ),
  );
  await tester.tap(find.text('Beta'));
  expect(selected, 1);
});
```

- [ ] **Step 2: Run test — expect FAIL (missing type)**

```bash
cd client && flutter test test/widgets/settings/workspace_section_tab_bar_test.dart
```

- [ ] **Step 3: Implement nav item + tab bar**

`WorkspaceSectionNavItem` as in the spec.

`WorkspaceSectionTabBar`: copy behavior from `HomeContentTabBar` / `HomeContentTabItem` (horizontal scroll, underline, `TpHover`). Prefer moving the widget bodies into `workspace_section_tab_bar.dart` and making `HomeContentTabBar` a thin delegate:

```dart
class HomeContentTabBar extends StatelessWidget {
  // same fields…
  @override
  Widget build(BuildContext context) => WorkspaceSectionTabBar(
        tabs: tabs,
        selectedIndex: selectedIndex,
        onSelect: onSelect,
      );
}
```

- [ ] **Step 4: Re-run test — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/settings/workspace_section_nav_item.dart \
  client/lib/widgets/settings/workspace_section_tab_bar.dart \
  client/lib/pages/home_workspace/home_workspace_content_header.dart \
  client/test/widgets/settings/workspace_section_tab_bar_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): share underline section tab bar

Extract WorkspaceSectionTabBar for narrow section nav and keep
HomeContentTabBar as a thin wrapper for identity shells.

EOF
)"
```

---

### Task 2: Adaptive shell — opt-in narrow tabs branch

**Files:**
- Modify: `client/lib/widgets/settings/workspace_section_host.dart`
- Create (if host > ~soft limit): `client/lib/widgets/settings/workspace_section_compact_shell.dart`
- Modify: `client/test/widgets/settings/workspace_section_host_test.dart`

- [ ] **Step 1: Write failing adaptive tests**

Add helpers that set `tester.view.physicalSize` / `devicePixelRatio` and tear down.

```dart
testWidgets('compact tabs: narrow shows tab strip not split', (tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(wrap(
    WorkspaceAdaptiveSectionPage(
      pageKey: const Key('p'),
      title: 'Skills',
      compactSectionTabs: true,
      items: [
        WorkspaceSectionNavItem(label: 'Installed', selected: true, onSelect: () {}),
        WorkspaceSectionNavItem(label: 'Discovery', selected: false, onSelect: () {}),
      ],
      body: const Text('Body'),
    ),
  ));
  expect(find.byType(WorkspaceSplitShell), findsNothing);
  expect(find.text('Installed'), findsOneWidget);
  expect(find.text('Discovery'), findsOneWidget);
  expect(find.text('Body'), findsOneWidget);
});

testWidgets('compact tabs: wide still splits', (tester) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(wrap(
    WorkspaceAdaptiveSectionPage(
      pageKey: const Key('p'),
      title: 'Skills',
      compactSectionTabs: true,
      items: [
        WorkspaceSectionNavItem(label: 'Installed', selected: true, onSelect: () {}),
        WorkspaceSectionNavItem(label: 'Discovery', selected: false, onSelect: () {}),
      ],
      body: const Text('Body'),
    ),
  ));
  expect(find.byType(WorkspaceSplitShell), findsOneWidget);
});

testWidgets('compact tabs: single item hides strip', (tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(wrap(
    WorkspaceAdaptiveSectionPage(
      pageKey: const Key('p'),
      title: 'Extensions',
      compactSectionTabs: true,
      items: [
        WorkspaceSectionNavItem(label: 'Installed', selected: true, onSelect: () {}),
      ],
      body: const Text('Body'),
    ),
  ));
  expect(find.byType(WorkspaceSectionTabBar), findsNothing);
  expect(find.text('Body'), findsOneWidget);
});
```

Keep existing non-Android desktop tests passing (`nav` without compact flag).

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd client && flutter test test/widgets/settings/workspace_section_host_test.dart
```

- [ ] **Step 3: Implement adaptive API**

Extend `WorkspaceAdaptiveSectionPage`:

```dart
const WorkspaceAdaptiveSectionPage({
  required this.pageKey,
  required this.title,
  required this.body,
  this.nav,
  this.items,
  this.compactSectionTabs = false,
  // existing subtitle / onBack / embedded…
}) : assert(
        !compactSectionTabs || (items != null && items.length > 0),
        'compactSectionTabs requires non-empty items',
      ),
      assert(
        compactSectionTabs || nav != null,
        'legacy mode requires nav',
      );
```

**Branch order in `build`:**

1. If `!compactSectionTabs && useAndroidHubNavigation(context)` → `WorkspaceSectionPage(body)` (unchanged out-of-scope).
2. Else if `compactSectionTabs && MediaQuery.sizeOf(context).width < WorkspacePanePolicy.narrowBreakpointWidth` → compact shell (header + optional `WorkspaceSectionTabBar` when `items!.length > 1` + body). Build selectedIndex from first `selected` item; `onSelect` → that item’s callback. For Android standalone (`!embedded`), suppress duplicate `WorkspacePaneHeader` title text when AppBar already shows title (pass `showTitle: false` or omit header title — keep tabs).
3. Else → `WorkspaceHubDesktopShell` with `nav: nav ?? _navFromItems(items!)`.

Helper `_navFromItems`:

```dart
Widget _navFromItems(List<WorkspaceSectionNavItem> items) {
  return WorkspaceHubNavList(
    sidebarStyle: true,
    entries: [
      for (final item in items)
        WorkspaceHubEntry(
          title: item.label,
          icon: item.icon ?? Icons.circle_outlined,
          selected: item.selected,
          onTap: item.onSelect,
        ),
    ],
  );
}
```

- [ ] **Step 4: Re-run host tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/settings/workspace_section_host.dart \
  client/lib/widgets/settings/workspace_section_compact_shell.dart \
  client/test/widgets/settings/workspace_section_host_test.dart
git commit -m "$(cat <<'EOF'
feat(settings): opt-in narrow section top tabs

Add compactSectionTabs + items on WorkspaceAdaptiveSectionPage so
narrow viewports show underline tabs without changing legacy hub pages.

EOF
)"
```

---

### Task 3: Opt-in library management pages

**Files:**
- Modify: `client/lib/pages/skills/skill_management_page.dart`
- Modify: `client/lib/pages/plugins/plugin_management_page.dart`
- Modify: `client/lib/pages/mcp/mcp_management_page.dart`
- Modify: `client/lib/pages/extensions/extension_management_page.dart`
- Test: extend `workspace_section_host_test.dart` **or** add one smoke widget test under `client/test/pages/skills/` that pumps `SkillManagementPage` at narrow width and finds section labels

- [ ] **Step 1: Write failing Skills smoke test (representative)**

Pump `SkillManagementPage(section: SkillSection.installed, embedded: true)` inside `TpTheme` + l10n + any required cubit fakes used by existing skill page tests. Narrow size 400×800. Expect tab labels for Installed / Discovery / Repos (use l10n English).

If existing skill tests are heavy, prefer asserting via a small harness that only builds the adaptive page wiring extracted as a testable helper — otherwise follow the lightest existing skill page test pattern in `client/test/pages/skills/`.

- [ ] **Step 2: Run — expect FAIL (no tabs yet on page)**

- [ ] **Step 3: Wire each management page**

Replace `nav: WorkspaceEnumNavPanel<…>(…)` with:

```dart
final sections = SkillSection.values; // or Plugin/Mcp/Extension
final l10n = context.l10n;
return WorkspaceAdaptiveSectionPage(
  // …
  compactSectionTabs: true,
  items: [
    for (final s in sections)
      WorkspaceSectionNavItem(
        label: s.title(l10n),
        icon: /* existing section icon helper */,
        selected: s == section,
        onSelect: () => select(s),
      ),
  ],
  // omit nav when items drive both layouts
  body: …,
);
```

Do **not** change `McpFormNavPage`.

- [ ] **Step 4: Run Skills smoke + host tests — PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/skills client/lib/pages/plugins \
  client/lib/pages/mcp/mcp_management_page.dart \
  client/lib/pages/extensions \
  client/test/pages/skills
git commit -m "$(cat <<'EOF'
feat(library): enable compact section tabs on manage pages

Opt Skills, Plugins, MCP, and Extensions into narrow top-tab
section navigation while keeping form routes on the hub path.

EOF
)"
```

---

### Task 4: Workspace manage opt-in

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_config_workspace.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_config_nav_panel.dart` (optional — may become unused for Adaptive if items replace it; keep if used elsewhere)
- Test: `client/test/pages/home_workspace/workspace_config_panel_compact_tabs_test.dart` (new)

- [ ] **Step 1: Write failing manage compact-tabs test**

Pump `WorkspaceConfigPanel` (or Adaptive-equivalent) at width 400 with fake workspace; expect tab labels for manage sections (English l10n). Tap a non-settings tab and verify `context.go` path / selection callback if testable without full router — otherwise verify tab widgets present and `WorkspaceSplitShell` absent.

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Opt in `WorkspaceConfigPanel`**

```dart
compactSectionTabs: true,
items: [
  for (final s in sections)
    WorkspaceSectionNavItem(
      label: s.title(l10n),
      icon: workspaceConfigSectionIcon(s),
      selected: s == section,
      onSelect: () => context.go(_managePath(s)),
    ),
],
```

Remove `nav:` when items cover wide layout.

- [ ] **Step 4: Run test — PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/workspace_config_workspace.dart \
  client/test/pages/home_workspace/workspace_config_panel_compact_tabs_test.dart
git commit -m "$(cat <<'EOF'
feat(workspace): compact tabs for manage sections

Use the same narrow section tab strip for workspace management
settings / skills / plugins / mcp / extensions.

EOF
)"
```

---

### Task 5: Router — always redirect library roots; drop Hub pages

**Files:**
- Modify: `client/lib/router/app_router.dart`
- Delete or gut: `SkillManagementHubPage`, `PluginManagementHubPage`, `McpManagementHubPage`, `ExtensionManagementHubPage` if unused
- Modify tests that pump Hub pages / Android root hub

- [ ] **Step 1: Write / update failing router or chrome test**

Assert `/skills` redirect target is always `/skills/installed` (no Android exception). Prefer a small pure helper if redirects are hard to pump; otherwise document manual check + update any existing router test.

Example helper (optional extract):

```dart
String? libraryRootRedirect(String path, {required bool isAndroid}) {
  // After change: ignore isAndroid for in-scope roots
}
```

Simpler: change redirect to unconditional and add a unit test next to router helpers if one exists.

- [ ] **Step 2: Change redirects**

For `/skills`, `/plugins`, `/mcp`, `/extensions`:

```dart
redirect: (context, state) => '/skills/installed', // matching root
```

Remove `if (Platform.isAndroid) return null;` and remove hub `pageBuilder` bodies (redirect-only routes need no page, or keep unreachable page removed).

- [ ] **Step 3: Delete dead Hub page classes + hub-only tests that only served Android roots**

Keep `WorkspaceHubPage` itself — still used by `/config` and team-config.

- [ ] **Step 4: `flutter test` affected files — PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/router/app_router.dart client/lib/pages/skills \
  client/lib/pages/plugins client/lib/pages/mcp client/lib/pages/extensions \
  client/test
git commit -m "$(cat <<'EOF'
fix(router): skip library hubs; land on installed section

Always redirect Skills/Plugins/MCP/Extensions roots to their
default section pages now that narrow tabs replace hub lists.

EOF
)"
```

---

### Task 6: `AndroidShellChrome` — exit library on back

**Files:**
- Modify: `client/lib/router/android_shell_chrome.dart`
- Test: `client/test/router/android_shell_chrome_test.dart` (create if missing)

- [ ] **Step 1: Write failing tests for exit helper / pop targets**

Cover:

- Skills detail / root → leave library (not `go('/skills')`)
- Plugins / Extensions / MCP section paths similarly
- Config / team-config / providers **unchanged**

Prefer testing pure path classification + documenting `leaveLibrary` behavior:

```dart
@visibleForTesting
bool isLibrarySectionPath(String path) { … }

@visibleForTesting
String? libraryExitLocation(String path) {
  // returns null if not a library leaf; caller then pop or go home
}
```

Or widget/router integration if the repo already tests chrome that way.

- [ ] **Step 2: Implement**

```dart
static void _leaveLibrary(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/home-v2');
  }
}
```

In `pop`:

- If skills / plugins / mcp (non-form) / extensions section or former hub root → `_leaveLibrary`
- Keep MCP form → `go(mcpInstalledRoute)`
- Do **not** `go('/skills')` when that redirects back to the same section

Update `isHubDetailPath` / `shouldHideDrawer` so library section paths still show AppBar back (treat as leaf). Include `/plugins/…` and `/extensions/…` (today often missing).

- [ ] **Step 3: Run chrome tests — PASS**

- [ ] **Step 4: Commit**

```bash
git add client/lib/router/android_shell_chrome.dart \
  client/test/router/android_shell_chrome_test.dart
git commit -m "$(cat <<'EOF'
fix(android): exit library sections without hub bounce

Back from Skills/Plugins/MCP/Extensions section pages pops or
returns home instead of navigating to a removed hub list.

EOF
)"
```

---

### Task 7: Verification

- [ ] **Step 1: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 2: Targeted tests**

```bash
cd client && flutter test \
  test/widgets/settings/workspace_section_tab_bar_test.dart \
  test/widgets/settings/workspace_section_host_test.dart \
  test/router/android_shell_chrome_test.dart \
  test/pages/home_workspace/workspace_config_panel_compact_tabs_test.dart
```

Plus any Skills smoke test path from Task 3.

- [ ] **Step 3: Manual checklist (Android / narrow desktop)**

1. Home `?global=skills` — top tabs; can switch Installed / Discovery / Repos  
2. Workspace manage — top tabs for all manage sections  
3. `/skills` opens installed with tabs; AppBar back leaves library  
4. Wide desktop — left nav unchanged  
5. `/config` Android hub list still works  

- [ ] **Step 4: Final commit only if verification left dirty files; otherwise done**

---

## Execution notes

- Prefer **subagent-driven-development** per task with TDD discipline.
- Do not opt-in `/config`, team-config, Providers, or `McpFormNavPage`.
- Default library section is **`installed`** for all four roots.
- Branch priority: legacy Android body-only **before** width tabs when `compactSectionTabs` is false.
