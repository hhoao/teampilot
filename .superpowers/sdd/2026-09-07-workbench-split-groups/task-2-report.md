# Task 2 Report: `WorkbenchCubit` group-aware API + bar state re-shape

Branch: `worktree-workbench-split-groups` (worktree of `C:/Users/haung/git/teampilot`).
Task 1 (`ead284332`, `workbench_split_layout.dart`) consumed as-is.

## What was built

### 1. `WorkspaceTabBar` re-shape — `client/lib/cubits/workbench/workbench_tab_bar.dart` (rewrite)

- Fields `center` / `floating` are now `WorkbenchGroupLayout` (was `TabStrip`).
- Constructor is **non-const** with nullable params defaulting to `singleGroupLayout()`:
  `WorkspaceTabBar({WorkbenchGroupLayout? center, WorkbenchGroupLayout? floating})`.
- `copyWith` unchanged in shape, now layout-typed.
- Because the constructor is no longer const, `WorkbenchState.bar`'s fallback changed from
  `const WorkspaceTabBar()` to a cached `static final WorkspaceTabBar _defaultBar` inside
  `WorkbenchState` (`client/lib/cubits/workbench/workbench_cubit.dart`).
  `bar(String) => byWorkspace[id] ?? _defaultBar;` as briefed.

### 2. `WorkbenchCubit` — `client/lib/cubits/workbench/workbench_cubit.dart` (rewrite)

Internal plumbing (per brief, verbatim helpers):

- `WorkbenchGroupLayout centerLayout(String)` / `floatingLayout(String)` (new).
- `_withCenter` / `_withFloating` write-back helpers.
- `_owningGroup(WorkspaceTabBar bar, WorkbenchTabId id) -> (WorkbenchGroupLayout, bool isCenter, String groupId)`:
  presence over every center group, then every floating group, then kind-routing to the
  focused group of the appropriate layout.
- `_mutateOwningGroup(ws, id, mutate)` — applies a `TabStripReducer` mutation to the owning
  group's strip and writes it back into a fresh `groups` map (immutability); no emit when
  the reducer returns the strip unchanged.
- `_mutateFocusedStrip(ws, {center, mutate})` — same for the focused group of a layout.
- `_mutateLayout(ws, {floating, mutate})` — runs a `SplitLayoutReducer` transform over one
  layout; null / identical returns do not emit.
- `_groupContainingTab(layout, tab)`, `_focusedStrip(layout)` static helpers.

Focused-group read APIs (single-group degenerate behavior-compatible):

- `WorkbenchTabId? centerActiveId(String)` — focused group's active.
- `List<WorkbenchTabId> centerOrder(String)` — focused group's order.
- `TabStrip centerFocusedStrip(String)` (new).
- `String centerFocusedGroupId(String)` (new).
- `WorkbenchTabId? floatingActiveId(String)` / `List<WorkbenchTabId> floatingOrder(String)` /
  `TabStrip floatingFocusedStrip(String)` — focused group of the floating layout.
- `bool centerLandingActive(String)`, `String? centerLandingInitialText(String)`,
  `int centerLandingInitialTextRevision(String)`, `String? centerLandingReferenceSessionId(String)`
  — focused-group reads.
- `bool canExitLanding(String)` — focused group.

**Added read API beyond the brief (Ruling 4):**

- `TabStrip mergedFloatingStrip(String workspaceId)` — whole-floating-surface view: every
  group's tabs in depth-first leaf order, preview/pinned sets unioned, `activeId` = focused
  group's active. Degenerate single-group layouts return the live strip instance as-is
  (landing fields preserved). Needed by consumers that mirror the *entire* floating panel
  (projection, bulk closes, run reconciliation, dirty-preview promotion) for which a
  focused-only read would be wrong once Task 6 introduces floating splits.

Mutation APIs — existing signatures kept, now group-aware inside:

- `openSession` / `openFile` / `openDiff` / `openFloating` / `openShell` / `openRun`:
  add into the **focused group** of the target layout, and focus that group. When the tab
  is already hosted by another group of the same layout, the add routes to that group
  (and focuses it) so no tab ever appears in two groups (invariant 3 of
  `validateLayout`). Returns the replaced preview tab as before.
- `close(ws, id)`: whole-layout `SplitLayoutReducer.remove` on the owning layout —
  a group emptied by the removal is pruned (sibling rolled up; sole root may go
  degenerate-empty). `_port.onTabRemoved` still called after bar removal, only when a
  removal happened. Absent id → returns null, no port call (as before).
- `activate`: `SplitLayoutReducer.activate` on center then floating — activates within the
  owning group **and focuses that group**.
- `pin` / `unpin` / `promote`: `_mutateOwningGroup` (presence routing preserved).
- `reorder` / `reorderFloating`: reorder the focused group's strip.
- `enterLanding` / `exitLanding` / `onSessionDeleted`: act on the focused group of center
  (`exitLanding` re-activates the focused group's `landingReturnTabId` via `activate`,
  which also re-focuses the owning group).
- `closeOthers` / `closeRight`: operate on the **owning** group's strip (tab context-menu
  semantics per brief). Absent-from-center → `const []` as before.
- `closeAll`: **group-scoped** (spec / brief migration rule) — closes the focused group's
  unpinned tabs; the focused group's pinned tabs survive; **other groups are untouched**.
  Removals run through `SplitLayoutReducer.remove` so an emptied non-root group is pruned
  and focus follows the surviving sibling. The existing degenerate landing-prefill
  clearing behavior (clear prefill when nothing was removed and no reference session)
  is preserved on the focused group.
- `clearWorkspace`: unchanged.

New group-mutation APIs (all carry `bool floating = false` per **Ruling 1**; the flag
selects `bar.floating` vs `bar.center`):

- `void splitTab(String ws, WorkbenchTabId tab, {required Axis axis, required bool before, bool floating = false})`
  — reducer `split`; reducer-null (absent tab / sole tab of its group) is silent.
- `void splitInto(String ws, WorkbenchTabId tab, String targetGroupId, {required Axis axis, required bool before, bool floating = false})`
  — reducer `splitInto` (added per Ruling 1's API list).
- `void moveTab(String ws, WorkbenchTabId tab, String targetGroupId, {bool floating = false})`.
- `void focusGroup(String ws, String groupId, {bool floating = false})`.
- `void commitSplitResize(String ws, {required List<bool> path, required double fraction, bool floating = false})`.
- `void toggleMaximizeGroup(String ws, String groupId, {bool floating = false})`.
- `void collapseSplitLayout(String ws, {bool floating = false})`.
- `void resetLayoutToSnapshot(String ws, WorkbenchGroupLayout? center, WorkbenchGroupLayout? floating)`
  — null argument keeps that surface's current layout (Task 9 restore entry).

### 3. Tests — `client/test/cubits/workbench/workbench_cubit_test.dart`

- All existing assertions migrated to focused-group reads
  (`centerOrder` / `centerActiveId` / `centerFocusedStrip(...)` / `floatingFocusedStrip(...)`
  / `centerLandingActive`); behavioral expectations unchanged (single-group equivalence).
- New `split groups` group with the brief's tests:
  - `splitTab moves tab into new group and focuses it`
  - `openSession lands in the focused group`
  - `activate focuses the owning group` — written with Ruling 2's corrected assertion
    `expect(cubit.centerFocusedGroupId(_ws), 'g0')` (the brief's
    `is SplitLeaf ? 'g0' : 'g0'` tautology dropped).
  - `close prunes the emptied group`
  - `enterLanding is group-scoped`
  - `closeAll keeps pinned tabs of the focused group only (group-scoped)` — see Deviations.
  - Plus (not in brief, added for coverage of the new APIs): `moveTab moves a tab between
    groups and prunes an emptied source`, `focusGroup / toggleMaximizeGroup /
    collapseSplitLayout round-trip`, `splitTab on a sole tab is a silent no-op`.
- `tab_strip_test.dart` untouched (strip-only, as the brief predicted).
- Task 1's `workbench_split_layout_test.dart` untouched.

### 4. Mechanical consumer migration (compile-fix only; no behavioral UI restructuring)

Every consumer of `bar(ws).center.X` / `bar(ws).floating.X` under `client/lib` and
`client/test` was migrated. Single-group degenerate behavior is preserved everywhere.

lib:

| File | Change |
|---|---|
| `client/lib/pages/workspace_shell/workspace_shell_tabs.dart` | `center.landingActive` select → `w.centerLandingActive(workspaceId)` |
| `client/lib/utils/workspace/workspace_new_chat_active.dart` | → `workbench.centerLandingActive(tabScopeId)` |
| `client/lib/pages/home_workspace/home_workspace_title_bar.dart` | → `w.centerLandingActive(activeTabKey!)` |
| `client/lib/app/app_shell.dart` | `composeLanding` closure → `workbenchCubit.centerLandingActive(...)` |
| `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart` | landing prefill selects → `centerLandingInitialText` / `centerLandingInitialTextRevision` / `centerLandingReferenceSessionId` |
| `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart` | `OpenSessionTabIds.fromCenterBarOrder(center.order, previewIds: center.previewIds)` → `centerFocusedStrip(tabScopeId)` order/previewIds |
| `client/lib/pages/chat/chat_page_shell.dart` | center order/active/pinned/preview reads → `centerOrder` / `centerActiveId` / one `centerFocusedStrip` for pinned+preview; the pin-toggle presence check → `centerFocusedStrip(workspaceId).pinnedIds.contains(...)`; removed the inner duplicate `context.read<WorkbenchCubit>()` |
| `client/lib/pages/chat/chat_page_structural_signal.dart` | order/active/landing reads → `centerOrder` / `centerActiveId` / `centerLandingActive` |
| `client/lib/widgets/workbench/workbench_shell_run_sync.dart` | floating strip → `mergedFloatingStrip` (run-tab reconciliation is whole-surface) |
| `client/lib/pages/floating_workspace/floating_workspace_panel.dart` | projection strip + pin/double-tap checks → `mergedFloatingStrip` |
| `client/lib/pages/floating_workspace/floating_workspace_close_shortcut.dart` | floating strip → `mergedFloatingStrip` |
| `client/lib/services/workbench/workbench_shell_launcher.dart` | `_resolveMostRecentShell` strip and `deferFirstTabUi` empty-check → `mergedFloatingStrip` |
| `client/lib/services/workbench/workbench_editor_opener.dart` | `_promoteDirtyFloatingPreview` preview sweep → `mergedFloatingStrip` (dirty previews in any group must promote) |
| `client/lib/services/workbench/workbench_strip_navigator.dart` | `next`/`previous` → `centerOrder` / `centerActiveId` |
| `client/lib/services/floating_workspace/close_floating_tab.dart` | `_isPinned` and bulk-close orders → `mergedFloatingStrip` (bulk closes are whole-surface) |
| `client/lib/widgets/right_tools/file_tree_panel.dart` | floating active file-preview path → `floatingActiveId` |
| `client/lib/services/editor/file_editor_toolbar.dart` | fallback scan over `byWorkspace` → reads `center.groups[center.focusedGroupId]?.activeId` |
| `client/lib/cubits/floating_workspace/floating_workspace_state.dart`, `floating_workspace_cubit.dart` | doc comments updated (`bar.floating` strip → floating layout) |

test (same mechanical pattern — focused reads for center, `mergedFloatingStrip` for
whole-floating-surface assertions, `centerFocusedStrip` for landing/return fields):

`test/cubits/workbench/workbench_landing_return_test.dart`,
`test/cubits/workbench/close_no_resurrect_test.dart`,
`test/cubits/floating_workspace/floating_workspace_projection_test.dart`,
`test/cubits/chat_cubit_test.dart`,
`test/services/workbench/workbench_strip_navigator_test.dart`,
`test/services/workbench/workbench_chat_bridge_test.dart`,
`test/services/workbench/workbench_editor_opener_test.dart`,
`test/services/workbench/workbench_shell_launcher_test.dart`,
`test/services/floating_workspace/floating_workspace_open_file_test.dart`,
`test/services/editor/markdown_preview_link_handler_test.dart`,
`test/services/commands/layout_command_registrar_test.dart`,
`test/pages/home_workspace/workspace/workspace_session_actions_test.dart`,
`test/pages/git_graph/open_git_graph_test.dart`, `git_graph_menus_test.dart`,
`git_graph_refs_menu_test.dart`, `test/pages/git_compare/open_git_compare_test.dart`,
`test/pages/floating_workspace/floating_workspace_tab_close_test.dart`,
`floating_workspace_host_test.dart`, `test/smoke/app_shell_smoke_test.dart`.

## Decisions & deviations

1. **Brief's `closeAll` split-group test was internally inconsistent — adjusted.**
   The brief's example test focuses `g0` (whose only tab `_s1` is pinned) and then asserts
   `expect(cubit.centerOrder(_ws), isEmpty)` with the comment "the focused (split) group's
   tab closed". No semantics can satisfy all three assertions: assertions 1–2 keep the
   pinned `_s1` in `g0`, `focusGroup(_ws, 'g0')` makes `g0` the focused group, and
   `centerOrder` reads the focused group — so it must be `[_s1]`, not empty, under *any*
   closeAll semantics (group-scoped, center-wide, or pin-protection-narrowing). Per the
   brief's own migration rule ("closeAll keeps pinned tabs of the focused group only
   (spec: group-scoped)"; closeOthers/closeRight are owning-group, closeAll is the focused
   group's strip), I implemented group-scoped closeAll and rewrote the test so the focused
   group actually contains a pinned + an unpinned tab:
   split `_s2` out (g1 focused), open `_s3` into g1, pin `_s2`, closeAll → removes `[_s3]`,
   keeps `[_s2]` pinned in g1, leaves g0 `[_s1]` untouched. The rewritten test verifies all
   three legs of the spec sentence.
2. **`floatingOrder` / `floatingActiveId` are focused-group reads** (parallel to the center
   trio, per the brief's "Same trio for floating"), and whole-surface consumers were
   migrated to the new `mergedFloatingStrip` (Ruling 4's leaf-merged escape hatch). No
   center-side merged read was needed: every center consumer is either focused-shell
   (chat page shell / structural signal — Task 5 restructures these) or degenerate-equal.
3. **Group-id recycling (Task 1 ruling 3)** respected: no lifetime-uniqueness assumptions
   anywhere; `_nextGroupId` max-suffix behavior untouched.
4. **`activate` no longer emits when nothing changes** (reducer returns the same layout
   instance). Previously it emitted an equal state which bloc deduped — observably
   equivalent.
5. `WorkspaceTabBar` dropped the now-unused `tab_strip.dart` import (doc reference only).

## Verification

Commands run (all from `client/`):

- `dart run tool/run_tests.dart test/cubits/workbench/workbench_cubit_test.dart` → 32/32 PASS.
- `dart run tool/run_tests.dart test/cubits/workbench test/cubits/floating_workspace test/services/workbench test/services/floating_workspace test/pages/floating_workspace` → 314/314 PASS.
- `dart run tool/run_tests.dart test/cubits/chat_cubit_test.dart test/pages/home_workspace/workspace/workspace_session_actions_test.dart test/pages/git_graph test/pages/git_compare test/services/editor/markdown_preview_link_handler_test.dart test/services/commands/layout_command_registrar_test.dart` → 108/108 PASS.
- `dart run tool/run_tests.dart test/smoke/app_shell_smoke_test.dart test/pages/workspace_shell` → smoke PASS; only failure is the known baseline `workspace_shell_sidebar_toggle_test`.
- `flutter analyze --no-fatal-infos --no-fatal-warnings` → no errors; no new warnings/infos in touched files (one transient `avoid_single_cascade_in_expression_statements` in the new test was fixed; the two `unused_import` warnings in `floating_workspace_state.dart` / `floating_workspace_cubit.dart` are pre-existing at HEAD — verified via `git show HEAD:...`).
- `dart run tool/run_tests.dart` (full suite, clean run) → `+8687 ~9 -11: Some tests failed`, with **all 11 failures inside the three known pre-existing baseline suites** (none in files touched by this task):
  - `test/pages/workspace_shell/workspace_shell_sidebar_toggle_test.dart` (1)
  - opencode config_profile suite (4): `opencode_agent_status_plugin_test`, `opencode_data_dir_env_test`, `opencode_external_directories_test`, `opencode_idle_plugin_test`
  - run/launch_adapter_client suite (6): all `launch_adapter_client_test` cases

  Note on flakiness: two earlier full-suite attempts that ran concurrently with other
  test batches (or an analyzer) showed a handful of extra failures outside those suites
  (e.g. `host_tty_wrap_test`, `launch_config_document_test`, `launch_config_schema_fields_test`,
  `plugin_provisioning_chain_test`); each of those passes in isolation on this branch —
  they are machine-contention artifacts of running two test batches at once, not
  regressions. The definitive result above is from a single clean run with nothing else
  executing.

## Not committed (per environment constraints)

- `client/packages/teampilot_tree_sitter/hook/build.dart` (local UTF-8 vswhere patch)
- `client/pubspec.lock`
