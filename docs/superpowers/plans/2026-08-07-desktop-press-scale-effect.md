# Desktop / Touch Press-Scale Click Effect — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `TpHover`-based buttons a subtle 4% press-scale animation by default (both desktop and touch), while full-width rows, menu rows, and native chrome opt out.

**Architecture:** Flip `TpHover.pressScale` default from `1.0` to `0.96` (the existing `AnimatedScale` + `_onTapDown/_onTapUp/_onTapCancel` bookkeeping already activate once `pressScale != 1.0`). `TpHoverRow` and ~27 row/menu/native-chrome call sites pass `pressScale: 1.0` to opt out.

**Tech Stack:** Flutter 3.44, `shared_ui` design system, `flutter_test`.

## Global Constraints

- `pressScale` default becomes `0.96`; scale applies on BOTH platforms (desktop scale + hover/cursor; touch scale layered over the InkWell ripple).
- Rows/menu/native chrome opt out with explicit `pressScale: 1.0` — they keep hover-only feedback.
- Keep every migrated call site's other params, children, and behavior unchanged; only add the single `pressScale: 1.0,` parameter where the plan lists it.
- `shared_ui` is a git submodule at `client/packages/shared_ui`; its changes are committed in the submodule first, then the parent bumps the pointer.
- Full gate before each commit: `flutter analyze --no-fatal-infos --no-fatal-warnings` and the task's tests. If the parent repo has unrelated in-progress edits that break whole-repo analyze/tests, verify per-file (`flutter analyze <file>` must be clean) and record pre-existing blockers in concerns — never touch unrelated WIP.

Spec: `docs/superpowers/specs/2026-08-07-desktop-press-scale-effect-design.md`.

---

### Task 1: `TpHover` default press scale + row/primitive opt-outs (shared_ui)

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/hover/tp_hover.dart`
- Modify: `client/packages/shared_ui/lib/src/components/hover/tp_hover_row.dart`
- Modify: `client/packages/shared_ui/lib/src/components/dialog/tp_dialog_nav_shell.dart`
- Modify: `client/packages/shared_ui/lib/src/components/sidebar/tp_sidebar_menu.dart`
- Test: `client/packages/shared_ui/test/components/hover/tp_hover_test.dart`

**Interfaces:**
- Produces: `TpHover.pressScale` defaults to `0.96`; `TpHoverRow` always passes `pressScale: 1.0` internally.

- [ ] **Step 1: Write the failing tests**

Append to `client/packages/shared_ui/test/components/hover/tp_hover_test.dart` (inside `main()`; the file's existing `wrap` helper stays):

```dart
  testWidgets('default pressScale animates to 0.96 while pressed', (tester) async {
    await tester.pumpWidget(
      wrap(TpHover(onTap: () {}, child: const SizedBox(width: 40, height: 20))),
    );
    // Default pressScale is now != 1.0, so the AnimatedScale wrapper exists.
    expect(find.byType(AnimatedScale), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TpHover)),
    );
    await tester.pump();
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      0.96,
    );

    await gesture.up();
    await tester.pump();
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      1.0,
    );
  });

  testWidgets('explicit pressScale 1.0 adds no AnimatedScale', (tester) async {
    await tester.pumpWidget(
      wrap(TpHover(pressScale: 1.0, onTap: () {}, child: const Text('x'))),
    );
    expect(find.byType(AnimatedScale), findsNothing);
  });
```

Run and verify the first test FAILS (default is still `1.0`, so `AnimatedScale` is absent → `find.byType(AnimatedScale)` finds nothing):

```
cd client/packages/shared_ui && flutter test test/components/hover/tp_hover_test.dart
```
Expected: `default pressScale animates to 0.96 while pressed` FAILS with "Expected: exactly one matching candidate ... but none found".

- [ ] **Step 2: Flip the `TpHover` default**

In `client/packages/shared_ui/lib/src/components/hover/tp_hover.dart`, change the `pressScale` constructor default (currently `this.pressScale = 1.0,`):

```dart
    this.pressScale = 0.96,
```

Update the field doc comment to reflect the new default:

```dart
  /// Scale applied while the pointer is down. `1.0` disables press feedback.
  /// Defaults to a subtle 4% shrink so buttons respond to press on both
  /// desktop and touch. Rows / menus set `1.0` to opt out.
  final double pressScale;
```

- [ ] **Step 3: Opt `TpHoverRow` out**

In `client/packages/shared_ui/lib/src/components/hover/tp_hover_row.dart`, in the `return TpHover( … )` construction (inside `_TpHoverRowState.build`), add the parameter alongside the existing `onHoverChanged: …` entry:

```dart
      onHoverChanged: (hovered) {
        setState(() => _hovered = hovered);
        widget.onHoverChanged?.call(hovered);
      },
      // Rows are hover-highlight + select surfaces, not press-scale buttons.
      pressScale: 1.0,
```

- [ ] **Step 4: Opt the shared_ui row sites out**

- In `client/packages/shared_ui/lib/src/components/dialog/tp_dialog_nav_shell.dart`, add `pressScale: 1.0,` to the `TpHover(` call for the **nav item** (the one with `borderRadius: BorderRadius.circular(12)` and `onTap: onTap`) and to the **dropdown entry** (the one with `onTap: () => onSelect(index)`).
- In `client/packages/shared_ui/lib/src/components/sidebar/tp_sidebar_menu.dart`, add `pressScale: 1.0,` to both `TpHover(` calls (the two sidebar menu-item surfaces).

- [ ] **Step 5: Verify shared_ui**

```
cd client/packages/shared_ui && flutter test
```
Expected: all pass — including the two new tests and the existing `pressScale wraps with AnimatedScale when not 1.0`.

```
cd client/packages/shared_ui && flutter analyze --no-fatal-infos --no-fatal-warnings
```
Expected: no new errors.

- [ ] **Step 6: Commit the submodule**

```bash
cd client/packages/shared_ui
git add lib/src/components/hover/tp_hover.dart lib/src/components/hover/tp_hover_row.dart lib/src/components/dialog/tp_dialog_nav_shell.dart lib/src/components/sidebar/tp_sidebar_menu.dart test/components/hover/tp_hover_test.dart
git commit -m "feat(hover): default press-scale to 0.96; opt rows out

TpHover now shrinks 4% while pressed on both desktop and touch. TpHoverRow
and shared_ui row/menu sites pass pressScale: 1.0 to keep hover-only feedback.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

- [ ] **Step 7: Bump the submodule pointer**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/packages/shared_ui
git commit -m "chore(submodule): bump shared_ui for default press-scale effect

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Opt out the lib row/menu/native-chrome call sites (23 files)

**Files:** modify each of the following `client/lib/…` files — add `pressScale: 1.0,` to the listed `TpHover(` call (the one whose child / site is described). No other change to that call; other params and children stay identical.

| # | File | `TpHover(` site |
|---|---|---|
| 1 | `widgets/compose/compose_trigger_field.dart` | the suggestion/menu row (`onTapDown: (_) => onSelected(suggestion)`) |
| 2 | `widgets/window_chrome_controls.dart` | the window chrome button (`onTap: () => widget.onPressed()`) |
| 3 | `pages/home_workspace/home_workspace_sidebar.dart` | the sidebar nav row (line ~239) |
| 4 | `pages/home_workspace/workspace/workspace_sidebar.dart` | the workspace sidebar row (line ~637) |
| 5 | `pages/home_workspace/workspaces_tab.dart` | the workspace tab row (line ~347) |
| 6 | `pages/home_workspace/home_workspace_team_tab.dart` | the team tab row (line ~282) |
| 7 | `pages/home_workspace/workspace/worktree_group_section.dart` | the worktree row (line ~503) |
| 8 | `pages/home_workspace/workspace/workspace_search_dialog.dart` | the search result row (line ~318) |
| 9 | `widgets/file_tree_node.dart` | the tree node row (line ~186) |
| 10 | `widgets/git/git_change_folder_tile.dart` | the folder tile row (line ~83) |
| 11 | `widgets/git/git_change_tile.dart` | the file tile row (line ~66) |
| 12 | `widgets/git/git_source_control_panel.dart` | the branch row (line ~597) |
| 13 | `widgets/notification/notification_list_tile.dart` | the notification tile row (line ~151) |
| 14 | `widgets/right_tools/tabbed_panel.dart` | the panel tab row (line ~118) |
| 15 | `widgets/right_tools/board_panel.dart` | the task card row (the `TpHover` with `onTap: onTap` + `#seq` child) |
| 16 | `widgets/notification/progress_activity_tile.dart` | the progress tile row (the `TpHover` with `onTap: onTap` + status icon child) |
| 17 | `pages/home_workspace/workspace/mixed_workspace_member_placement_panel.dart` | the member placement row (the `TpHover` with `onTap: onTap` + label Column child) |
| 18 | `widgets/settings/workspace_hub_shell.dart` | the hub nav row (line ~109) |
| 19 | `widgets/workspace_status_bar/resource_manager_panel.dart` | the resource row (line ~273) |
| 20 | `widgets/workspace_status_bar/ssh_hosts_panel.dart` | the ssh host row (line ~238) |
| 21 | `pages/mcp/mcp_registries_section.dart` | the registry row (line ~373) |
| 22 | `pages/mcp/mcp_form_page.dart` | the metadata toggle row (line ~213) |
| 23 | `pages/team_config/team_config_nav_panel.dart` | the add-tile row (line ~85) |

**Test:** `cd client && flutter test test/widgets/compose test/widgets/git test/widgets/notification test/widgets/right_tools test/pages/home_workspace test/pages/mcp test/pages/team_config --exclude-tags integration` (run after the change; any dir that fails to LOAD due to unrelated WIP is a pre-existing blocker — record and move on).

- [ ] **Step 1: Add the opt-out parameter to each site**

For each row of the table above, open the file, find the `TpHover(` described, and add the parameter line inside it:

```dart
        // Full-width row / menu surface — no press-scale.
        pressScale: 1.0,
```

Place it anywhere in the named-argument list (e.g. right after `onTap:`). Keep every existing argument and the child subtree byte-identical.

- [ ] **Step 2: Verify**

```
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```
Expected: no errors (if unrelated WIP breaks whole-repo analyze, run `flutter analyze <file>` per changed file and confirm "No issues found!").

```
cd client && flutter test test/widgets/compose test/pages/home_workspace --exclude-tags integration
```
Expected: PASS for the dirs that load.

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/compose/compose_trigger_field.dart lib/widgets/window_chrome_controls.dart lib/pages/home_workspace/home_workspace_sidebar.dart lib/pages/home_workspace/workspace/workspace_sidebar.dart lib/pages/home_workspace/workspaces_tab.dart lib/pages/home_workspace/home_workspace_team_tab.dart lib/pages/home_workspace/workspace/worktree_group_section.dart lib/pages/home_workspace/workspace/workspace_search_dialog.dart lib/widgets/file_tree_node.dart lib/widgets/git/git_change_folder_tile.dart lib/widgets/git/git_change_tile.dart lib/widgets/git/git_source_control_panel.dart lib/widgets/notification/notification_list_tile.dart lib/widgets/right_tools/tabbed_panel.dart lib/widgets/right_tools/board_panel.dart lib/widgets/notification/progress_activity_tile.dart lib/pages/home_workspace/workspace/mixed_workspace_member_placement_panel.dart lib/widgets/settings/workspace_hub_shell.dart lib/widgets/workspace_status_bar/resource_manager_panel.dart lib/widgets/workspace_status_bar/ssh_hosts_panel.dart lib/pages/mcp/mcp_registries_section.dart lib/pages/mcp/mcp_form_page.dart lib/pages/team_config/team_config_nav_panel.dart
git commit -m "feat(ui): opt full-width rows/menus/native chrome out of press-scale

Compact buttons/chips gain the default 0.96 press-scale (from shared_ui);
rows, menu rows, and window chrome keep hover-only feedback.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Full gate + verification

**Files:** none (verification only)

- [ ] **Step 1: Full analyze + test**

```
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```
Expected: analyze 0 errors; test suite passes (transient parallel-load failures that pass individually are acceptable; real failures must be fixed).

- [ ] **Step 2: Manual desktop check**

Run the app on Linux. Verify:
1. Primary buttons (compose send/attach/enhance/voice/chips, icon buttons) shrink ~4% while pressed and spring back on release.
2. Full-width rows (sidebar, list tiles, git tiles, notifications), menu/suggestion rows, and window chrome controls show NO scale.
3. Hover color + hand cursor behavior unchanged; disabled buttons still arrow.

- [ ] **Step 3: Manual touch check (Android)**

Run on an Android device/emulator. Verify: buttons show ripple + subtle scale on tap; rows ripple only (no scale); nothing crashes.

---

## Self-Review Notes

- **Spec coverage:** Task 1 = spec §1 (`TpHover` default) + §2 (`TpHoverRow`) + the shared_ui rows in §3's table; Task 2 = the lib rows in spec §3's table (23 files); Task 3 = spec Testing/Risks. No spec requirement is left without a task.
- **Placeholder scan:** every code step has concrete code; the Task 2 table gives exact file + site for each `pressScale: 1.0` insertion.
- **Type consistency:** only new name is the unchanged `pressScale` parameter (existing type `double`); `AnimatedScale` is asserted at `0.96` / `1.0` in tests.
