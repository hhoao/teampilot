# Workbench Locked Groups Design

Date: 2026-09-11
Status: Draft for user review

## Problem

TeamPilot already supports VS Code-style workbench split groups. Each
`WorkbenchGroupLayout` contains a split tree, one `TabStrip` per leaf group,
and a focused group. New tabs currently open into the focused group. This is
undesirable when one pane is being used as a stable reference while another
pane is used for exploration.

The workbench needs a per-group lock. A locked group remains usable, but is no
longer a destination for automatic new-tab placement. If no unlocked group is
available, TeamPilot creates a new adjacent group for the new tab.

## Goals

- Lock and unlock individual center-workbench and floating-workspace groups.
- Keep locked groups usable for activation, manual tab moves, reordering,
  closing, and explicit split actions.
- Route automatically opened new tabs to an unlocked group.
- Create a new adjacent, unlocked group when every existing group is locked.
- Persist lock state with the existing per-workspace workbench layout snapshot.
- Preserve the current single-group behavior when no group is locked.
- Keep all existing tab ownership and split-layout invariants intact.

## Non-goals

- Locking individual tabs. Existing tab pinning remains a separate feature for
  close protection and preview promotion.
- Preventing focus, editing, dragging, or closing inside a locked group.
- Changing explicit split, move, or drag semantics.
- Adding a global workspace preference that locks every group at once.

## State model

Extend `WorkbenchGroupLayout` in
`client/lib/cubits/workbench/workbench_split_layout.dart` with:

```dart
final Set<String> lockedGroupIds;
```

The set contains live leaf group ids. It is layout-level metadata rather than
part of `TabStrip`, because the lock belongs to a pane, not to the tabs inside
that pane.

`copyWith`, equality, and `validateLayout` must include the new field. The
layout invariants become:

1. Tree leaves and `groups` keys are a one-to-one mapping.
2. No group is empty except the sole degenerate root group.
3. Focus and maximize references identify live groups.
4. Every tab id appears in exactly one group.
5. Every locked group id identifies a live group.

The factory `singleGroupLayout` starts with an empty lock set. Existing code
constructing layouts must continue to work through the default value.

## Reducer behavior

`SplitLayoutReducer` remains the single pure writer for layout state.

Add:

```dart
WorkbenchGroupLayout toggleLock(
  WorkbenchGroupLayout layout,
  String groupId,
);

WorkbenchGroupLayout? openInNewGroup(
  WorkbenchGroupLayout layout, {
  required String targetGroupId,
  required WorkbenchTabId tab,
  required Axis axis,
  required bool before,
});
```

`toggleLock` is a no-op for a non-live group. Newly created groups are always
unlocked. Removing or pruning a group removes its id from
`lockedGroupIds`. Moving tabs between groups does not change either group's
lock state. Collapsing/resetting the layout clears all locks because the
operation creates a new single-group layout state.

`openInNewGroup` is needed because the tab does not yet belong to a source
group. It inserts a new sibling leaf beside `targetGroupId`, creates an active
single-tab strip for the new group, focuses that group, and leaves the target
group's tabs unchanged. It returns null only when the target is not a live
leaf or the tab already exists in the layout.

## Automatic new-tab placement

Centralize automatic placement in `WorkbenchCubit`; all center and floating
open methods use the same policy for their selected layout.

1. If the tab already exists, preserve the existing behavior: operate on its
   owning group and focus that group. A lock does not prevent reopening or
   activating an existing tab.
2. If the focused group is unlocked, open the new tab there.
3. Otherwise, inspect live leaves in depth-first order and choose the nearest
   unlocked group by leaf-order distance from the focused group. If both sides
   are equally near, prefer the group to the right/bottom (the later leaf).
4. If no unlocked group exists, call `openInNewGroup` beside the focused group
   using a horizontal right split. The new group is unlocked and focused.

Opening into a fallback group focuses that group so the newly opened tab is
immediately visible. Manual drag/move and explicit split commands continue to
work regardless of the destination group's lock state.

The placement policy must be shared by `openSession`, `openFile`, `openDiff`,
`openFloating`, `openShell`, and `openRun`; no feature-level `if locked`
branches are allowed.

## UI

Each group header exposes a lock toggle. In the center Session bar, the
button is placed in the existing Tab-row trailing area, immediately after the
new-tab button and before any other trailing actions:

```text
[ session tabs ... ] [ + ] [ lock group ] [ other actions ]
```

This makes the control available beside the tabs while keeping it outside the
scrollable tab list. Every split group gets its own copy of this control.

The left sidebar's already-open Session rows also expose the same action in
their existing right-click / long-press menu. A row rendered from the split
group open-session section carries its owning `groupId`; the menu label is
“Lock Group” or “Unlock Group” and acts on that owning group. This remains
available even when the Session tab bar is hidden. The menu must not lock the
manual Session category/group; it locks the workbench split group containing
the opened Session tab.

For the floating workspace:

- in multi-group mode, put the button at the right end of each pane's slim
  group header, after that group's tabs;
- in single-group or narrow mode, the outer floating title bar is the only
  group header, so put it after `+` and before the window-level minimize /
  maximize / close controls.

The button states are:

- unlocked: open-lock affordance and tooltip “Lock Group”;
- locked: closed-lock affordance and tooltip “Unlock Group”.

The center header, sidebar menu, and floating group header all dispatch the
same group-aware cubit operation. The lock icon should be visible without
relying on hover, so the state is discoverable on desktop and mobile. The
focused group highlight remains independent from the lock indicator.

Add the corresponding English and Chinese strings only to
`client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb`.

## Persistence and migration

Extend each layout snapshot with:

```json
{
  "lockedGroupIds": ["g0", "g2"]
}
```

Older snapshots without the field decode as an empty set. During restore,
unknown or pruned group ids are discarded. A corrupt snapshot still follows
the existing single-group fallback and starts unlocked. Lock state is saved by
the existing debounced workbench layout persistence flow; no new storage file
or lifecycle is required.

## Error handling and edge cases

- Toggling a missing group is a no-op and must not emit state.
- Pruning the last non-root locked group repairs the lock set before emitting.
- If the focused group is locked and exactly one other group is unlocked, the
  new tab opens in that other group; no new split is created.
- If all groups are locked, the automatically created sibling is unlocked,
  focused, and receives the new tab.
- If the layout is a single locked group with no tabs, opening a new tab still
  creates a sibling group rather than silently violating the lock.
- The lock does not affect `centerActiveId` / `floatingActiveId`; these remain
  focused-group reads.
- Narrow-screen rendering continues to show only the focused group. Lock state
  and the split tree survive and are restored when the layout widens.

## Testing

Reducer tests in
`client/test/cubits/workbench/workbench_split_layout_test.dart`:

- lock toggle sets and clears the id;
- invalid group toggle is a no-op;
- new groups created by `openInNewGroup` are unlocked and focused;
- remove/prune clears a locked group id;
- collapse clears locks;
- validation rejects orphan lock ids;
- snapshot round-trip preserves locks;
- old snapshots without `lockedGroupIds` restore unlocked.

Workbench cubit tests in
`client/test/cubits/workbench/workbench_cubit_test.dart`:

- new tabs use the focused unlocked group;
- a locked focused group routes to the nearest unlocked group;
- equal-distance fallback prefers the later leaf;
- all locked groups cause an adjacent unlocked group to be created;
- reopening an existing tab still targets its owning group even when locked;
- center and floating layouts apply the same policy independently.

Widget tests for the center and floating group headers verify the lock icon,
tooltip/callback, and that focus highlighting remains independent. Sidebar
tests verify that an opened Session row's context menu targets its owning split
group and remains available when the tab bar is hidden. Persistence tests
verify the new field through the existing snapshot repository.

All tests use `cd client && dart run tool/run_tests.dart ...`; never invoke
`flutter test` directly.

## Affected components

| Change | File |
| --- | --- |
| Lock metadata, reducer, validation, snapshot codec | `client/lib/cubits/workbench/workbench_split_layout.dart` |
| Automatic target-group selection and lock API | `client/lib/cubits/workbench/workbench_cubit.dart` |
| Center lock affordance in Session Tab row | `client/lib/pages/workbench/workbench_group_host.dart`, `client/lib/pages/workspace_shell/workspace_shell.dart` |
| Opened Session row context menu | `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart`, `client/lib/widgets/sidebar_session_tile.dart` |
| Floating lock affordance | `client/lib/pages/floating_workspace/floating_group_host.dart`, `client/lib/pages/floating_workspace/floating_workspace_panel.dart` |
| Snapshot compatibility | `client/lib/repositories/workbench_layout_snapshot_repository.dart` and codec callers |
| Localized labels/tooltips | `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb` |
| Reducer, cubit, widget, and persistence tests | corresponding `client/test/...` files |
