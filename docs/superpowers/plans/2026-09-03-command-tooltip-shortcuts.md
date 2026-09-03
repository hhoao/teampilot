# Command Tooltip Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Append the effective keyboard shortcut to hover tooltips on the sidebar visibility toggle, right-tools visibility toggle, and workspace sidebar Search tile.

**Architecture:** Add a small `commandTooltip(BuildContext, label, commandId)` helper that reads `ShortcutCubit` overrides, resolves the first effective chord via `KeybindingResolver` + `formatKeyChord`, and returns `label (chord)` or plain `label`. Wire the three call sites to use it and rebuild when overrides change. No command registration or click-path changes.

**Tech Stack:** Flutter, flutter_bloc (`ShortcutCubit`, `LayoutCubit`), existing command catalog / keybinding stack under `client/lib/services/commands/`.

**Spec:** `docs/superpowers/specs/2026-09-03-command-tooltip-shortcuts-design.md`

## Global Constraints

- All paths below are relative to the repo root `/home/hhoa/git/hhoa/teampilot`; Flutter commands run from `client/`.
- Format: `{label} ({chord})` when bound; `{label}` when unbound / missing Cubit / unknown command. No empty parentheses.
- First chord only when multiple bindings exist.
- Reuse `formatKeyChord` + `defaultIsMacOS()` — do not hardcode platform strings in call sites.
- Do not change default chords, `CommandBus` handlers, or click behavior.
- Do not bake chords into l10n ARB strings.
- Out of scope: content-search (`workspaceContentSearch`), shortcut badges, broader chrome rollout.
- Before declaring done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Run focused tests via `dart run tool/run_tests.dart <path>` (not raw `flutter test`).
- Do not stage unrelated dirty working-tree files (sidebar_session_tile / l10n / fastforge / final-fix-report).
- Commit messages follow recent repo style (`feat:`, `test:`, `docs:`); no force-push; only commit when the task step says so.

## File map

| File | Role |
|------|------|
| Create `client/lib/services/commands/command_tooltip.dart` | Shared helper |
| Create `client/test/services/commands/command_tooltip_test.dart` | Helper widget tests |
| Modify `client/lib/pages/workspace_shell/workspace_shell_tabs.dart` | Sidebar + right-tools tooltips |
| Modify `client/test/pages/workspace_shell/workspace_shell_sidebar_toggle_test.dart` | Assert sidebar tooltip chord |
| Modify `client/test/pages/workspace_shell/workspace_shell_tabs_test.dart` | Assert right-tools tooltip chord |
| Modify `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart` | Search tile tooltip |
| Create or extend a focused search-tile tooltip test under `client/test/pages/home_workspace/workspace/` | Assert search Tooltip message |

---

### Task 1: `commandTooltip` helper

**Files:**
- Create: `client/lib/services/commands/command_tooltip.dart`
- Create: `client/test/services/commands/command_tooltip_test.dart`

**Interfaces:**
- Consumes: `ShortcutCubit.state.overrides`, `KeybindingResolver.effectiveBindings`, `CommandCatalog.v1`, `formatKeyChord`, `defaultIsMacOS`, `CommandIds`.
- Produces: `String commandTooltip(BuildContext context, String label, String commandId)` — Tasks 2 and 3 call this.

- [ ] **Step 1: Write the failing tests**

Create `client/test/services/commands/command_tooltip_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/repositories/keybinding_repository.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/command_tooltip.dart';
import 'package:teampilot/services/commands/key_chord.dart';
import 'package:teampilot/services/commands/key_chord_formatter.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  Future<String> pumpLabel(
    WidgetTester tester, {
    required String label,
    required String commandId,
    ShortcutCubit? shortcuts,
  }) async {
    late String result;
    await tester.pumpWidget(
      shortcuts == null
          ? MaterialApp(
              home: Builder(
                builder: (context) {
                  result = commandTooltip(context, label, commandId);
                  return const SizedBox.shrink();
                },
              ),
            )
          : BlocProvider<ShortcutCubit>.value(
              value: shortcuts,
              child: MaterialApp(
                home: Builder(
                  builder: (context) {
                    result = commandTooltip(context, label, commandId);
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
    );
    return result;
  }

  testWidgets('appends formatted default chord', (tester) async {
    final shortcuts = ShortcutCubit(repository: KeybindingRepository());
    addTearDown(shortcuts.close);
    await shortcuts.load();

    final chord = formatKeyChord(
      KeyChord(key: 'b', mods: [KeyChordMod.mod]),
      isMacOS: defaultIsMacOS(),
    );
    final result = await pumpLabel(
      tester,
      label: 'Hide sidebar',
      commandId: CommandIds.toggleSidebar,
      shortcuts: shortcuts,
    );
    expect(result, 'Hide sidebar ($chord)');
  });

  testWidgets('returns label only when unbound', (tester) async {
    final shortcuts = ShortcutCubit(repository: KeybindingRepository());
    addTearDown(shortcuts.close);
    await shortcuts.load();
    await shortcuts.unbind(CommandIds.toggleSidebar);

    final result = await pumpLabel(
      tester,
      label: 'Hide sidebar',
      commandId: CommandIds.toggleSidebar,
      shortcuts: shortcuts,
    );
    expect(result, 'Hide sidebar');
  });

  testWidgets('returns label only without ShortcutCubit', (tester) async {
    final result = await pumpLabel(
      tester,
      label: 'Hide sidebar',
      commandId: CommandIds.toggleSidebar,
    );
    expect(result, 'Hide sidebar');
  });

  testWidgets('formats double-tap Shift for workspace search', (tester) async {
    final shortcuts = ShortcutCubit(repository: KeybindingRepository());
    addTearDown(shortcuts.close);
    await shortcuts.load();

    final chord = formatKeyChord(
      KeyChord.doubleTapShift(),
      isMacOS: defaultIsMacOS(),
    );
    final result = await pumpLabel(
      tester,
      label: 'Search',
      commandId: CommandIds.workspaceSearch,
      shortcuts: shortcuts,
    );
    expect(result, 'Search ($chord)');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run (from `client/`):

```bash
dart run tool/run_tests.dart test/services/commands/command_tooltip_test.dart
```

Expected: FAIL — `command_tooltip.dart` does not exist / `commandTooltip` is undefined.

- [ ] **Step 3: Write minimal implementation**

Create `client/lib/services/commands/command_tooltip.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/shortcut_cubit.dart';
import 'command_catalog.dart';
import 'key_chord.dart';
import 'key_chord_formatter.dart';
import 'keybinding_resolver.dart';

/// Label with the first effective shortcut for [commandId], e.g. `Hide sidebar (Ctrl+B)`.
///
/// Returns [label] unchanged when the command is unbound, missing from the
/// catalog, or [ShortcutCubit] is not in the tree.
String commandTooltip(BuildContext context, String label, String commandId) {
  try {
    final overrides = context.read<ShortcutCubit>().state.overrides;
    final bindings = KeybindingResolver.effectiveBindings(
      catalog: CommandCatalog.v1,
      overrides: overrides,
    );
    final chords = bindings[commandId] ?? const <KeyChord>[];
    if (chords.isEmpty) return label;
    final chord = formatKeyChord(chords.first, isMacOS: defaultIsMacOS());
    return '$label ($chord)';
  } catch (_) {
    return label;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
dart run tool/run_tests.dart test/services/commands/command_tooltip_test.dart
```

Expected: PASS (all four tests).

- [ ] **Step 5: Commit**

```bash
git add \
  client/lib/services/commands/command_tooltip.dart \
  client/test/services/commands/command_tooltip_test.dart
git commit -m "$(cat <<'EOF'
feat(commands): add commandTooltip helper for chrome hints

EOF
)"
```

---

### Task 2: Sidebar + right-tools visibility toggle tooltips

**Files:**
- Modify: `client/lib/pages/workspace_shell/workspace_shell_tabs.dart`
- Modify: `client/test/pages/workspace_shell/workspace_shell_sidebar_toggle_test.dart`
- Modify: `client/test/pages/workspace_shell/workspace_shell_tabs_test.dart`

**Interfaces:**
- Consumes: `commandTooltip` from Task 1; `CommandIds.toggleSidebar`, `CommandIds.toggleSecondarySidebar`.
- Produces: `TpIconButton.tooltip` strings that include the effective chord; widgets rebuild when `ShortcutCubit.state.overrides` changes.

- [ ] **Step 1: Write the failing widget assertions**

In `client/test/pages/workspace_shell/workspace_shell_sidebar_toggle_test.dart`:

1. Add imports:

```dart
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/repositories/keybinding_repository.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/key_chord.dart';
import 'package:teampilot/services/commands/key_chord_formatter.dart';
```

2. Wrap the existing pump tree with `BlocProvider<ShortcutCubit>.value` (create + `load()` + tearDown close), same pattern as LayoutCubit.

3. After first `pumpAndSettle`, add:

```dart
      final expectedChord = formatKeyChord(
        KeyChord(key: 'b', mods: [KeyChordMod.mod]),
        isMacOS: defaultIsMacOS(),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byKey(AppKeys.sidebarVisibilityButton)),
      )!;
      // narrowLeftSuppressed ⇒ effectiveOpen false ⇒ "Show sidebar"
      expect(
        tester
            .widget<TpIconButton>(find.byKey(AppKeys.sidebarVisibilityButton))
            .tooltip,
        '${l10n.sidebarPanelVisible} ($expectedChord)',
      );
```

In `client/test/pages/workspace_shell/workspace_shell_tabs_test.dart`:

1. Add the same ShortcutCubit / formatter / CommandIds imports (plus `shared_ui` if needed for `TpIconButton`).
2. Provide `ShortcutCubit` (load + tearDown) in `MultiBlocProvider`.
3. After pump, before or after the tap, assert:

```dart
      final expectedChord = formatKeyChord(
        KeyChord(
          key: 'b',
          mods: [KeyChordMod.mod, KeyChordMod.alt],
        ),
        isMacOS: defaultIsMacOS(),
      );
      final button = tester.widget<TpIconButton>(
        find.byKey(AppKeys.rightToolsVisibilityButton),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byKey(AppKeys.rightToolsVisibilityButton)),
      )!;
      // compose landing + default override null ⇒ not visible ⇒ Show tools panel
      expect(
        button.tooltip,
        '${l10n.rightToolsPanelVisible} ($expectedChord)',
      );
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
dart run tool/run_tests.dart \
  test/pages/workspace_shell/workspace_shell_sidebar_toggle_test.dart \
  test/pages/workspace_shell/workspace_shell_tabs_test.dart
```

Expected: FAIL — tooltip is still the bare l10n string (no chord suffix).

- [ ] **Step 3: Wire tooltips in `workspace_shell_tabs.dart`**

Add imports:

```dart
import '../../cubits/shortcut_cubit.dart';
import '../../services/commands/command_ids.dart';
import '../../services/commands/command_tooltip.dart';
import '../../services/commands/key_chord.dart';
```

Update `WorkspaceShellRightToolsVisibilityToggle.build` so the widget rebuilds when overrides change. At the start of `build` (before or inside the existing `BlocBuilder`):

```dart
    context.select<ShortcutCubit, Map<String, List<KeyChord>>>(
      (c) => c.state.overrides,
    );
```

Then change the `tooltip:` line to:

```dart
          tooltip: commandTooltip(
            context,
            visible ? l10n.rightToolsPanelHidden : l10n.rightToolsPanelVisible,
            CommandIds.toggleSecondarySidebar,
          ),
```

In `WorkspaceShellSidebarVisibilityToggle.build`, the same `context.select` on overrides, then:

```dart
          tooltip: commandTooltip(
            context,
            effectiveOpen
                ? l10n.sidebarPanelHidden
                : l10n.sidebarPanelVisible,
            CommandIds.toggleSidebar,
          ),
```

Every test that pumps these widgets must provide `ShortcutCubit` (Task 2 Step 1). Production shell already mounts it in `app_shell.dart`. Do not catch-and-ignore a missing Cubit at the select site — let missing providers fail loudly in tests; `commandTooltip` itself still swallows missing Cubit for the string.
- [ ] **Step 4: Run tests to verify they pass**

```bash
dart run tool/run_tests.dart \
  test/pages/workspace_shell/workspace_shell_sidebar_toggle_test.dart \
  test/pages/workspace_shell/workspace_shell_tabs_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add \
  client/lib/pages/workspace_shell/workspace_shell_tabs.dart \
  client/test/pages/workspace_shell/workspace_shell_sidebar_toggle_test.dart \
  client/test/pages/workspace_shell/workspace_shell_tabs_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): show shortcut chords on pane visibility tooltips

EOF
)"
```

---

### Task 3: Workspace sidebar Search tile tooltip

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart`
- Create: `client/test/pages/home_workspace/workspace/workspace_sidebar_search_tooltip_test.dart`

**Interfaces:**
- Consumes: `commandTooltip`, `CommandIds.workspaceSearch`.
- Produces: optional `tooltip` on `_SidebarActionTile`; Search row shows `Tooltip` with label + double-Shift chord.

- [ ] **Step 1: Write the failing test**

Create `client/test/pages/home_workspace/workspace/workspace_sidebar_search_tooltip_test.dart`. Mirror the provider setup from `workspace_sidebar_embed_footer_test.dart` (ChatCubit, AutomationCubit, WorktreeCubit, AgentAttentionCubit, SessionGroupsCubit, WorkbenchCubit as needed), and **also** provide `ShortcutCubit` (load + tearDown).

Assert after pump:

```dart
      final expectedChord = formatKeyChord(
        KeyChord.doubleTapShift(),
        isMacOS: defaultIsMacOS(),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byKey(AppKeys.searchSidebarTile)),
      )!;
      final tooltip = tester.widget<Tooltip>(
        find.descendant(
          of: find.byKey(AppKeys.searchSidebarTile),
          matching: find.byType(Tooltip),
        ),
      );
      // If Tooltip wraps the key (ancestor), use find.ancestor instead:
      // find.ancestor(of: find.byKey(AppKeys.searchSidebarTile), matching: find.byType(Tooltip))
      expect(tooltip.message, '${l10n.workspaceSearchTitle} ($expectedChord)');
```

Use whichever finder matches the wrap order chosen in Step 3 (`Tooltip` outside the keyed child is typical → `find.ancestor`).

Keep the harness minimal: if full `WorkspaceSidebar` is heavy, pump only what embed-footer already pumps — copy that file's `pumpWidget` tree and add `ShortcutCubit`.

- [ ] **Step 2: Run test to verify it fails**

```bash
dart run tool/run_tests.dart \
  test/pages/home_workspace/workspace/workspace_sidebar_search_tooltip_test.dart
```

Expected: FAIL — no `Tooltip` under/around `searchSidebarTile`, or message is wrong.

- [ ] **Step 3: Implement tile tooltip + Search wiring**

In `workspace_sidebar.dart`:

1. Add imports for `ShortcutCubit`, `CommandIds`, `command_tooltip.dart`, `key_chord.dart` (if select needs the type — map select may not).

2. Extend `_SidebarActionTile`:

```dart
  const _SidebarActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.tooltip,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final String? tooltip;
```

At end of `_SidebarActionTileState.build`, replace `return tile;` with:

```dart
    final tip = widget.tooltip;
    if (tip == null || tip.isEmpty) return tile;
    return Tooltip(message: tip, child: tile);
  }
```

3. On the Search `_SidebarActionTile` call site, select overrides then pass tooltip:

```dart
            Builder(
              builder: (context) {
                context.select<ShortcutCubit, Map<String, List<KeyChord>>>(
                  (c) => c.state.overrides,
                );
                return _SidebarActionTile(
                  key: AppKeys.searchSidebarTile,
                  icon: Icons.search_outlined,
                  label: l10n.workspaceSearchTitle,
                  tooltip: commandTooltip(
                    context,
                    l10n.workspaceSearchTitle,
                    CommandIds.workspaceSearch,
                  ),
                  enabled: true,
                  onTap: throttledTap(
                    'workspace_sidebar_search',
                    () => _openWorkspaceSearch(context),
                  ),
                );
              },
            ),
```

(Alternatively put the `select` + `commandTooltip` in the parent `build` without an inner `Builder` if `ShortcutCubit` is already above — prefer the simplest form that compiles.)

Do **not** add a tooltip to the New conversation tile in this task.

- [ ] **Step 4: Run test to verify it passes**

```bash
dart run tool/run_tests.dart \
  test/pages/home_workspace/workspace/workspace_sidebar_search_tooltip_test.dart
```

Expected: PASS. Fix the Tooltip ancestor/descendant finder if the wrap order differs.

- [ ] **Step 5: Commit**

```bash
git add \
  client/lib/pages/home_workspace/workspace/workspace_sidebar.dart \
  client/test/pages/home_workspace/workspace/workspace_sidebar_search_tooltip_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): show workspace search shortcut in sidebar tooltip

EOF
)"
```

---

### Task 4: Verification gate

**Files:** none new (analyze + full test suite)

**Interfaces:** none

- [ ] **Step 1: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no new errors/warnings from the files touched in Tasks 1–3.

- [ ] **Step 2: Full test run**

```bash
cd client && dart run tool/run_tests.dart
```

Expected: PASS (or only pre-existing unrelated failures — do not ignore failures in the new/changed tests).

- [ ] **Step 3: Commit only if analyze/test forced doc/comment-only fixes**

If Step 1–2 required small fixups, commit them:

```bash
git add <only fixup files>
git commit -m "$(cat <<'EOF'
fix(ui): polish command tooltip wiring after verify

EOF
)"
```

If nothing to commit, skip.

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Helper `commandTooltip` | Task 1 |
| Format `{label} ({chord})` / label-only fallback | Task 1 |
| First chord only + `formatKeyChord` | Task 1 |
| Sidebar toggle tooltip | Task 2 |
| Right-tools toggle tooltip (`toggleSecondarySidebar`) | Task 2 |
| Rebuild on override change | Tasks 2–3 (`context.select` on overrides) |
| Workspace Search tile tooltip | Task 3 |
| No click-path / CommandBus / default chord changes | All (explicit non-goals) |
| Helper + widget tests | Tasks 1–3 |
| Full analyze + tests | Task 4 |
