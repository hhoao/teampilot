# Workbench Locked Groups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add VS Code-style per-pane locking so automatic new tabs avoid locked workbench groups and create a new adjacent group when every group is locked.

**Architecture:** Store lock state as `Set<String> lockedGroupIds` on the existing immutable `WorkbenchGroupLayout`, not on `TabStrip`. Keep all mutations in `SplitLayoutReducer`, expose one group-lock API and one automatic target-selection policy from `WorkbenchCubit`, and reuse the same policy for center and floating layouts. Render the control in each group header, including the center Session tab-row trailing area, the floating group headers, and the existing left-sidebar Session context menu.

**Tech Stack:** Flutter, flutter_bloc/Cubit, Equatable, shared_ui `TpIconButton` and action menus, existing split-layout snapshot JSON, ARB localization, Dart tests through `tool/run_tests.dart`.

## Global Constraints

- Split semantics remain move-only for existing tabs; automatic all-locked placement creates a new sibling only for a tab that is not yet in the layout.
- Lock state is per layout and per group; center and floating layouts are independent.
- Existing tab pinning remains tab-level close protection and is not reused as group locking.
- New tabs use the focused unlocked group, then the nearest unlocked leaf, then a new right-side sibling when no unlocked leaf exists.
- Existing tabs reopen in their owning group even when that group is locked.
- New groups are always unlocked; removing/pruning a group removes its lock id; collapsing the layout clears all locks.
- Narrow rendering shows only the focused group while retaining lock state and the split tree.
- Tests must run through `cd client && dart run tool/run_tests.dart ...`; never invoke raw `flutter test`.
- Before claiming completion: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Edit localization sources only in `client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb`; do not hand-edit generated localization Dart files.
- Preserve unrelated existing worktree changes; stage only files belonging to this feature in each commit.

## File Map

- `client/lib/cubits/workbench/workbench_split_layout.dart`: immutable lock metadata, reducer operations, invariants, and snapshot compatibility.
- `client/lib/cubits/workbench/workbench_cubit.dart`: automatic new-tab target selection and public `toggleGroupLock` API for both layouts.
- `client/lib/widgets/workbench/workbench_group_lock_button.dart`: shared visible lock/unlock affordance and localized tooltip.
- `client/lib/pages/workspace_shell/workspace_shell.dart`: optional group-control slot in the Session tab-row trailing area.
- `client/lib/pages/workbench/workbench_group_host.dart` and `client/lib/pages/chat/chat_page_shell.dart`: center group lock wiring.
- `client/lib/pages/floating_workspace/floating_group_host.dart` and `client/lib/pages/floating_workspace/floating_workspace_panel.dart`: floating group header and single-group title-bar wiring.
- `client/lib/widgets/sidebar_session_tile.dart` and `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart`: opened Session row context-menu wiring with owning split-group ids.
- `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`: lock/unlock labels and tooltips.
- Matching `client/test/...` files: reducer, Cubit, shared button, center/floating headers, sidebar menu, and persistence coverage.

---

### Task 1: Add lock metadata and pure reducer operations

**Files:**
- Modify: `client/lib/cubits/workbench/workbench_split_layout.dart:77-137, 238-405, 408-518`
- Test: `client/test/cubits/workbench/workbench_split_layout_test.dart`

**Interfaces:**
- Consumes: existing `WorkbenchGroupLayout`, `SplitNode`, `TabStrip`, `TabStripReducer`, and snapshot helpers.
- Produces: `lockedGroupIds`, `SplitLayoutReducer.toggleLock`, `SplitLayoutReducer.openInNewGroup({preview, activate})`, and snapshot support used by later tasks.

The reducer method must expose this exact shape so the Cubit can preserve
preview and activation semantics:

```dart
WorkbenchGroupLayout? openInNewGroup(
  WorkbenchGroupLayout layout, {
  required String targetGroupId,
  required WorkbenchTabId tab,
  required Axis axis,
  required bool before,
  bool preview = false,
  bool activate = true,
});
```

- [ ] **Step 1: Write failing reducer tests for lock state and new-group creation**

Add tests beside the existing split/reducer tests. Use the current `_seed` helper and a two-tab layout; the essential assertions are:

```dart
test('toggleLock sets and clears a live group lock', () {
  const reducer = SplitLayoutReducer();
  final base = _seed(_s1, _s2);
  final locked = reducer.toggleLock(base, 'g0');
  expect(locked.lockedGroupIds, {'g0'});
  expect(reducer.toggleLock(locked, 'g0').lockedGroupIds, isEmpty);
});

test('toggleLock ignores a missing group', () {
  const reducer = SplitLayoutReducer();
  final base = _seed(_s1, _s2);
  expect(reducer.toggleLock(base, 'missing'), same(base));
});

test('openInNewGroup creates an unlocked focused sibling for a new tab', () {
  const reducer = SplitLayoutReducer();
  final base = _seed(_s1, _s2).copyWith(lockedGroupIds: {'g0'});
  final next = reducer.openInNewGroup(
    base,
    targetGroupId: 'g0',
    tab: _s3,
    axis: Axis.horizontal,
    before: false,
  );
  expect(next, isNotNull);
  final layout = next!;
  expect(layout.groups['g0']!.order, [_s1, _s2]);
  expect(layout.lockedGroupIds, {'g0'});
  expect(layout.focusedGroupId, isNot('g0'));
  final newGroup = layout.focusedGroupId;
  expect(layout.groups[newGroup]!.order, [_s3]);
  expect(layout.lockedGroupIds.contains(newGroup), isFalse);
  expect(validateLayout(layout), isTrue);
});

test('openInNewGroup replaces a sole empty root instead of retaining an empty pane', () {
  const reducer = SplitLayoutReducer();
  final base = singleGroupLayout().copyWith(lockedGroupIds: {'g0'});
  final next = reducer.openInNewGroup(
    base,
    targetGroupId: 'g0',
    tab: _s3,
    axis: Axis.horizontal,
    before: false,
  )!;
  expect(next.root, isA<SplitLeaf>());
  expect(next.groups[next.focusedGroupId]!.order, [_s3]);
  expect(validateLayout(next), isTrue);
});

test('openInNewGroup rejects an existing tab or missing target', () {
  const reducer = SplitLayoutReducer();
  final base = _seed(_s1, _s2);
  expect(
    reducer.openInNewGroup(
      base,
      targetGroupId: 'g0',
      tab: _s1,
      axis: Axis.horizontal,
      before: false,
    ),
    isNull,
  );
  expect(
    reducer.openInNewGroup(
      base,
      targetGroupId: 'missing',
      tab: _s3,
      axis: Axis.horizontal,
      before: false,
    ),
    isNull,
  );
});
```

Also add assertions for pruning and reset:

```dart
test('remove clears a pruned group lock and collapse clears all locks', () {
  const reducer = SplitLayoutReducer();
  final split = reducer.split(
    _seed(_s1, _s2),
    tab: _s2,
    axis: Axis.horizontal,
    before: false,
  )!;
  final locked = split.copyWith(lockedGroupIds: {split.focusedGroupId});
  final pruned = reducer.remove(locked, _s2)!;
  expect(pruned.lockedGroupIds, isEmpty);
  expect(reducer.collapse(locked).lockedGroupIds, isEmpty);
});

test('validateLayout rejects an orphan lock id', () {
  final invalid = _seed(_s1).copyWith(lockedGroupIds: {'missing'});
  expect(validateLayout(invalid), isFalse);
});
```

- [ ] **Step 2: Run the focused reducer test and verify it fails**

Run:

```bash
cd client && dart run tool/run_tests.dart test/cubits/workbench/workbench_split_layout_test.dart
```

Expected: FAIL because `WorkbenchGroupLayout` has no `lockedGroupIds`, and the reducer methods are not defined.

- [ ] **Step 3: Implement the immutable field and reducer methods**

Add a defaulted field and include it in `copyWith` and Equatable props:

```dart
final Set<String> lockedGroupIds;

WorkbenchGroupLayout copyWith({
  SplitNode? root,
  Map<String, TabStrip>? groups,
  Object? focusedGroupId = _unset,
  Object? maximizedGroupId = _unset,
  Set<String>? lockedGroupIds,
}) => WorkbenchGroupLayout(
  root: root ?? this.root,
  groups: groups ?? this.groups,
  focusedGroupId: focusedGroupId == _unset
      ? this.focusedGroupId
      : focusedGroupId as String,
  maximizedGroupId: maximizedGroupId == _unset
      ? this.maximizedGroupId
      : maximizedGroupId as String?,
  lockedGroupIds: lockedGroupIds ?? this.lockedGroupIds,
);
```

Use `const {}` as the constructor default and `singleGroupLayout` default. `toggleLock` must return the same layout instance for an invalid group, otherwise copy the set and toggle the id. `openInNewGroup` accepts `bool preview = false` and `bool activate = true`, uses the existing leaf replacement helper, allocates the next non-recycled group id, preserves the target strip, adds a one-tab strip through `TabStripReducer.add(..., preview: preview, activate: activate)`, focuses the new id when requested, and leaves the new id out of `lockedGroupIds`. When the target is the sole empty root, replace that root leaf with the new group instead of producing an empty non-root group.

When `remove` or `moveTab` prunes a source group, copy `lockedGroupIds` and remove that group id before constructing the next layout. `collapse` must construct the new single group with an empty lock set. Add the orphan-lock check to `validateLayout`.

- [ ] **Step 4: Add snapshot encoding/decoding and compatibility tests**

Extend `toSnapshot` with a `lockedGroupIds` array. In `layoutFromSnapshot`, accept a missing/non-list field as an empty set, keep only ids that survive tree pruning, and pass the result to `WorkbenchGroupLayout`. Add:

```dart
test('snapshot round-trip preserves locked groups', () {
  final layout = _seed(_s1, _s2).copyWith(lockedGroupIds: {'g0'});
  final restored = layoutFromSnapshot(
    toSnapshot(layout),
    tabResolves: (_) => true,
  )!;
  expect(restored.lockedGroupIds, {'g0'});
});

test('old snapshots without lock field restore unlocked', () {
  final snapshot = toSnapshot(_seed(_s1, _s2))..remove('lockedGroupIds');
  final restored = layoutFromSnapshot(snapshot, tabResolves: (_) => true)!;
  expect(restored.lockedGroupIds, isEmpty);
});
```

- [ ] **Step 5: Run reducer and snapshot tests, then commit**

Run:

```bash
cd client && dart run tool/run_tests.dart test/cubits/workbench/workbench_split_layout_test.dart
```

Expected: PASS. Then commit only this task's model and test files:

```bash
git add client/lib/cubits/workbench/workbench_split_layout.dart client/test/cubits/workbench/workbench_split_layout_test.dart
git commit -m "feat(workbench): add locked split-group state"
```

### Task 2: Route automatic new tabs around locked groups

**Files:**
- Modify: `client/lib/cubits/workbench/workbench_cubit.dart:326-362, 673-853`
- Test: `client/test/cubits/workbench/workbench_cubit_test.dart`

**Interfaces:**
- Consumes: `WorkbenchGroupLayout.lockedGroupIds`, `SplitLayoutReducer.openInNewGroup`, existing center/floating open methods.
- Produces: `WorkbenchCubit.toggleGroupLock(String workspaceId, String groupId, {bool floating = false})`; all automatic open methods use the lock-aware policy.

- [ ] **Step 1: Write failing Cubit tests for placement policy**

Extend the existing Cubit harness with these scenarios:

```dart
test('new tab in a locked focused group creates an unlocked sibling', () {
  final cubit = WorkbenchCubit();
  cubit.openSession(_ws, 's1');
  cubit.openSession(_ws, 's2');
  final focused = cubit.centerLayout(_ws).focusedGroupId;
  cubit.toggleGroupLock(_ws, focused);
  cubit.openSession(_ws, 's3');
  final layout = cubit.centerLayout(_ws);
  expect(layout.groups[layout.focusedGroupId]!.order, [_s3]);
  expect(layout.lockedGroupIds, {focused});
  expect(layout.lockedGroupIds.contains(layout.focusedGroupId), isFalse);
});

test('locked focus routes a new tab to the nearest unlocked leaf', () {
  final cubit = WorkbenchCubit()
    ..openSession(_ws, 's1')
    ..openSession(_ws, 's2');
  cubit.splitTab(_ws, _s2, axis: Axis.horizontal, before: false);
  cubit.openSession(_ws, 's3');
  cubit.splitTab(_ws, _s3, axis: Axis.horizontal, before: false);
  final before = cubit.centerLayout(_ws);
  final middle = before.leafGroupIds[1];
  cubit.toggleGroupLock(_ws, middle);
  cubit.focusGroup(_ws, middle);
  cubit.openSession(_ws, 's4');
  final after = cubit.centerLayout(_ws);
  expect(
    after.groups[after.leafGroupIds[2]]!.order,
    contains(WorkbenchTabId.session('s4')),
  );
});

test('reopening an existing tab still activates its locked owning group', () {
  final cubit = WorkbenchCubit();
  cubit.openSession(_ws, 's1');
  cubit.openSession(_ws, 's2');
  final owner = cubit.centerLayout(_ws).focusedGroupId;
  cubit.toggleGroupLock(_ws, owner);
  cubit.revealTabBeside(_ws, _s2, axis: Axis.horizontal, before: false);
  cubit.openSession(_ws, 's2');
  expect(cubit.centerActiveId(_ws), _s2);
  expect(cubit.centerLayout(_ws).focusedGroupId, isNot(owner));
});
```

Add the same all-locked scenario for `openFloating` and assert the floating layout changes without changing the center layout. Add a three-leaf equal-distance case and assert the later leaf wins.

- [ ] **Step 2: Run the focused Cubit tests and verify they fail**

Run:

```bash
cd client && dart run tool/run_tests.dart test/cubits/workbench/workbench_cubit_test.dart
```

Expected: compile/test failure because the public lock API and lock-aware target selection do not exist.

- [ ] **Step 3: Implement the shared target-selection algorithm**

Add the public API through `_mutateLayout`:

```dart
void toggleGroupLock(
  String workspaceId,
  String groupId, {
  bool floating = false,
}) => _mutateLayout(
  workspaceId,
  floating: floating,
  mutate: (layout) => _lr.toggleLock(layout, groupId),
);
```

In `_openIntoLayout`, first resolve an existing tab by ownership exactly as today. Only when the tab is absent should the policy run:

```dart
String? _automaticTargetGroup(WorkbenchGroupLayout layout) {
  final focused = layout.focusedGroupId;
  if (!layout.lockedGroupIds.contains(focused)) return focused;
  final leaves = layout.leafGroupIds;
  final origin = leaves.indexOf(focused);
  for (var distance = 1; distance < leaves.length; distance++) {
    final later = origin + distance;
    if (later < leaves.length &&
        !layout.lockedGroupIds.contains(leaves[later])) {
      return leaves[later];
    }
    final earlier = origin - distance;
    if (earlier >= 0 &&
        !layout.lockedGroupIds.contains(leaves[earlier])) {
      return leaves[earlier];
    }
  }
  return null;
}
```

This checks the later leaf first at each distance, implementing the specified right/bottom tie-break. If the helper returns a target, add the tab there and focus that group. If it returns null, call `openInNewGroup` with the focused group, `axis: Axis.horizontal`, `before: false`, and the original `preview`/`activate` values; emit the returned layout. The all-locked path must not call the existing-tab `TabStripReducer.add` path twice. When the focused group is the sole empty root, the reducer replaces it in place and still returns a valid single-group layout.

Ensure `openSession`, `openFile`, `openDiff`, `openFloating`, `openShell`, and `openRun` all continue through `_openIntoLayout`.

- [ ] **Step 4: Run Cubit tests and commit**

Run:

```bash
cd client && dart run tool/run_tests.dart test/cubits/workbench/workbench_cubit_test.dart
```

Expected: PASS. Commit:

```bash
git add client/lib/cubits/workbench/workbench_cubit.dart client/test/cubits/workbench/workbench_cubit_test.dart
git commit -m "feat(workbench): route new tabs around locked groups"
```

### Task 3: Add the shared lock button and center Session-bar entry point

**Files:**
- Create: `client/lib/widgets/workbench/workbench_group_lock_button.dart`
- Modify: `client/lib/pages/workspace_shell/workspace_shell.dart:12-175`
- Modify: `client/lib/pages/workbench/workbench_group_host.dart:48-120, 203-375`
- Modify: `client/lib/pages/chat/chat_page_shell.dart:170-215`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/widgets/workbench/workbench_group_lock_button_test.dart`
- Test: `client/test/pages/workspace_shell_test.dart`

**Interfaces:**
- Consumes: `locked`, `onToggle`, and `WorkbenchCubit.toggleGroupLock`.
- Produces: reusable `WorkbenchGroupLockButton({required bool locked, required VoidCallback onToggle})`; optional `WorkspaceShell.tabBarTrailing` rendered after `newChatButton`.

- [ ] **Step 1: Add localization keys and write the button/widget tests**

Add matching keys named `workbenchLockGroup` and `workbenchUnlockGroup` to both ARB files, with English and Chinese values. Regenerate localization output with `cd client && flutter gen-l10n`; do not manually edit generated Dart.

Test the shared button with a minimal `MaterialApp` and localization delegate fixture:

```dart
testWidgets('lock button exposes state-specific icon and callback', (tester) async {
  var toggles = 0;
  await tester.pumpWidget(_localizedHost(
    WorkbenchGroupLockButton(
      locked: false,
      onToggle: () => toggles++,
    ),
  ));
  expect(find.byIcon(Icons.lock_open_outlined), findsOneWidget);
  await tester.tap(find.byType(WorkbenchGroupLockButton));
  expect(toggles, 1);
  await tester.pumpWidget(_localizedHost(
    WorkbenchGroupLockButton(locked: true, onToggle: () => toggles++),
  ));
  expect(find.byIcon(Icons.lock_outlined), findsOneWidget);
});
```

Add a `WorkspaceShell` test that supplies `tabBarTrailing: const KeyedSubtree(...)` and asserts the widget is after the new-chat control in the row. Keep the existing `actions` behavior unchanged.

- [ ] **Step 2: Run the new widget tests and verify they fail**

Run:

```bash
cd client && dart run tool/run_tests.dart test/widgets/workbench/workbench_group_lock_button_test.dart test/pages/workspace_shell_test.dart
```

Expected: compile failure because the widget, ARB getters, and `tabBarTrailing` parameter do not yet exist.

- [ ] **Step 3: Implement the shared button and Session-row slot**

Implement the button with `TpIconButton`, using `Icons.lock_open_outlined` when unlocked and `Icons.lock_outlined` when locked. The tooltip must be the localized Lock/Unlock Group label. Add `Widget? tabBarTrailing` to `WorkspaceShell`, pass it through `WorkspaceShellTabRow.trailing`, and combine it with existing trailing actions in a small `Row` so the order is `[newChatButton][lock button][existing actions]`.

Add `isGroupLocked` and `onToggleGroupLock` to `WorkbenchGroupHost`. Pass the shared button as `tabBarTrailing` with a callback that calls `workbench.toggleGroupLock(workspaceId, groupId)`. In `chat_page_shell.dart`, read `layout.lockedGroupIds.contains(groupId)` in the group builder and pass the value to the host. Do not put the control in the top-level team action row.

- [ ] **Step 4: Run center/header tests and commit**

Run:

```bash
cd client && dart run tool/run_tests.dart test/widgets/workbench/workbench_group_lock_button_test.dart test/pages/workspace_shell_test.dart test/pages/workbench/workbench_group_host_test.dart
```

Expected: PASS. Commit only the shared button, center wiring, localization sources, and their tests:

```bash
git add client/lib/widgets/workbench/workbench_group_lock_button.dart client/lib/pages/workspace_shell/workspace_shell.dart client/lib/pages/workbench/workbench_group_host.dart client/lib/pages/chat/chat_page_shell.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/widgets/workbench/workbench_group_lock_button_test.dart client/test/pages/workspace_shell_test.dart client/test/pages/workbench/workbench_group_host_test.dart
git commit -m "feat(workbench): add center group lock control"
```

### Task 4: Add floating-window group header entry points

**Files:**
- Modify: `client/lib/pages/floating_workspace/floating_group_host.dart:75-321`
- Modify: `client/lib/pages/floating_workspace/floating_workspace_panel.dart:1027-1107, 1230-1285`
- Test: `client/test/pages/floating_workspace/floating_split_test.dart`

**Interfaces:**
- Consumes: shared `WorkbenchGroupLockButton`, `WorkbenchCubit.toggleGroupLock`, `WorkbenchGroupLayout.lockedGroupIds`.
- Produces: lock control in every floating group header; single/narrow mode places the focused group's control in the outer title bar.

- [ ] **Step 1: Write failing floating header tests**

Extend the existing split test to assert that each multi-group slim header has one lock control and that toggling it changes only the corresponding floating group. Add a single-group test that finds the lock control between the floating add button and window chrome. Assert that multi-group mode does not add a misleading global lock button to the outer title-bar chrome.

- [ ] **Step 2: Run the focused floating tests and verify they fail**

Run:

```bash
cd client && dart run tool/run_tests.dart test/pages/floating_workspace/floating_split_test.dart
```

Expected: FAIL because the floating hosts do not expose a lock control.

- [ ] **Step 3: Wire the multi-group and single-group locations**

Add `isGroupLocked` and `onToggleGroupLock` to `FloatingGroupHost`. In `_FloatingGroupHeaderStrip`, wrap the current `FloatingWorkspaceTabBar` and the lock button in a trailing `Row`; keep the button outside the horizontally managed tab content.

Extend `_TitleBar` with an optional `groupAction`. In `floating_workspace_panel.dart`, pass the focused group's lock button only when the title bar is the group's visible header (`layout.groups.length == 1 || !widget.splitEnabled`); pass null in wide multi-group mode because each slim header owns its own lock. Insert the single/narrow button after `FloatingWorkspaceAddButton` and before `FloatingWorkspaceChrome`.

- [ ] **Step 4: Run floating tests and commit**

Run:

```bash
cd client && dart run tool/run_tests.dart test/pages/floating_workspace/floating_split_test.dart
```

Expected: PASS. Commit:

```bash
git add client/lib/pages/floating_workspace/floating_group_host.dart client/lib/pages/floating_workspace/floating_workspace_panel.dart client/test/pages/floating_workspace/floating_split_test.dart
git commit -m "feat(workbench): add floating group lock controls"
```

### Task 5: Add lock/unlock to opened Session sidebar menus

**Files:**
- Modify: `client/lib/widgets/sidebar_session_tile.dart:34-45, 166-275, 679-780`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart:817-862, 864-945`
- Test: `client/test/pages/home_workspace/workspace/workspace_sidebar_split_groups_test.dart`
- Test: `client/test/widgets/sidebar_session_tile_test.dart`

**Interfaces:**
- Consumes: optional `SidebarSessionTile` callback/state for the owning workbench group, `SplitSessionGroup` group ids, and the shared Cubit API.
- Produces: “Lock Group” / “Unlock Group” in every opened Session row's existing right-click and Android long-press menu, targeting the actual center workbench group.

- [ ] **Step 1: Write failing sidebar menu tests**

Build a split layout with two open sessions and render the split open-session section. Right-click each Session row and assert the menu label reflects that row's group lock state. Select the menu item and assert only that group is locked. Add a flat/single-group case so the menu remains available when the Session Tab row is hidden, using the sole focused group id.

The test must distinguish workbench group locking from manual Session category grouping: selecting the menu item must change `workbench.centerLayout(...).lockedGroupIds`, not `SessionGroupsCubit` state.

- [ ] **Step 2: Run the focused sidebar tests and verify they fail**

Run:

```bash
cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_sidebar_split_groups_test.dart
```

Expected: FAIL because the Session tile has no workbench group-lock callback or menu entry.

- [ ] **Step 3: Wire optional tile context-menu state and group ids**

Add optional fields to `SidebarSessionTile`:

```dart
final bool? workbenchGroupLocked;
final VoidCallback? onToggleWorkbenchGroupLock;
```

When the callback is non-null and the Session is open, insert a `TpActionMenuItem` near the existing “Open to Side” action. Use the lock/unlock icon and localized label, close the menu, and invoke the callback. Keep archived/non-open rows free of this action.

For split rows, extend `SplitSessionGroup` with `locked` and include it in equality/hash code. Populate it from `layout.lockedGroupIds` in `SplitSessionGroups.fromWorkbench`, then pass the value and callback to each `SidebarSessionTile` in `_RunningSplitGroupsSection`.

For the flat `_RunningSessionsSection`, pass the current center focused group id and lock state to every opened Session row. The callback must call `workbench.toggleGroupLock(tabScopeId, groupId)`; it must not infer a group from the Session's manual category membership.

- [ ] **Step 4: Run sidebar tests and commit**

Run:

```bash
cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_sidebar_split_groups_test.dart test/widgets/sidebar_session_tile_test.dart
```

Expected: PASS. Commit:

```bash
git add client/lib/widgets/sidebar_session_tile.dart client/lib/pages/home_workspace/workspace/workspace_sidebar.dart client/test/pages/home_workspace/workspace/workspace_sidebar_split_groups_test.dart client/test/widgets/sidebar_session_tile_test.dart
git commit -m "feat(workbench): expose group lock in session sidebar"
```

### Task 6: Verify persistence and full integration behavior

**Files:**
- Inspect: `client/lib/repositories/workbench_layout_snapshot_repository.dart`, `client/lib/services/workbench/workbench_layout_persistence.dart`
- Test: `client/test/repositories/workbench_layout_snapshot_repository_test.dart`
- Test: `client/test/services/workbench/workbench_layout_persistence_test.dart`

**Interfaces:**
- Consumes: `toSnapshot` / `layoutFromSnapshot` changes from Task 1 and the existing debounced persistence observer.
- Produces: proof that locks survive workspace restore, unknown group ids are discarded, and old snapshots remain compatible.

- [ ] **Step 1: Add persistence tests**

Save a center/floating layout with different locked group ids through the existing snapshot repository, reload it, and assert both sets survive independently. Add a snapshot containing an unknown lock id and assert restore succeeds with only live ids. Add an old snapshot without the field and assert both layouts restore unlocked.

- [ ] **Step 2: Run persistence tests and fix only snapshot integration issues**

Run:

```bash
cd client && dart run tool/run_tests.dart test/repositories/workbench_layout_snapshot_repository_test.dart
```

Expected: PASS with no new storage path. If a repository test uses exact JSON maps, update only the expected shape to include `lockedGroupIds`.

- [ ] **Step 3: Run targeted regression tests**

Run:

```bash
  cd client && dart run tool/run_tests.dart \
  test/cubits/workbench/workbench_split_layout_test.dart \
  test/cubits/workbench/workbench_cubit_test.dart \
  test/widgets/workbench/workbench_group_lock_button_test.dart \
  test/pages/workbench/workbench_group_host_test.dart \
  test/pages/floating_workspace/floating_split_test.dart \
  test/pages/home_workspace/workspace/workspace_sidebar_split_groups_test.dart \
  test/widgets/sidebar_session_tile_test.dart \
  test/repositories/workbench_layout_snapshot_repository_test.dart \
  test/services/workbench/workbench_layout_persistence_test.dart
```

Expected: PASS, including existing split, tab pin, sidebar, and floating behaviors.

- [ ] **Step 4: Run analyzer and full suite before claiming completion**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart
```

Expected: analyzer clean and full test suite passing. If the full suite is slow, run it in the background using the repository test runner and poll its result; do not run a second test process concurrently.

- [ ] **Step 5: Review the final diff and commit any integration fixes**

Run:

```bash
git diff --check
git status --short
git diff --stat HEAD~6..HEAD
```

Confirm no unrelated dirty-worktree files were staged, no generated localization source was hand-edited, and all five user entry points behave consistently. If integration fixes are needed, stage only the feature paths listed in Tasks 1–5 (never use `git add -A`) and commit them with `fix(workbench): polish locked group integration`.

## Self-Review Checklist

- State model, reducer, validation, prune behavior, collapse behavior, and JSON compatibility are covered by Task 1.
- Focused, nearest, tie-break, all-locked auto-create/replacement, existing-tab reopen, and center/floating independence are covered by Task 2.
- Center Session Tab trailing placement is covered by Task 3.
- Floating multi-group slim-header and single/narrow title-bar placement are covered by Task 4.
- Left opened-Session right-click/long-press behavior, including hidden-tab-bar fallback and manual-group separation, is covered by Task 5.
- Persistence, old snapshots, unknown lock ids, analyzer, and full test suite are covered by Task 6.
- No task relies on an undefined later interface; all new public names are introduced in Task 1 or Task 2 before UI tasks consume them.
