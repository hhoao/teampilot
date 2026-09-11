# Task 2 Report: Route automatic new tabs around locked groups

## Status

Implemented Task 2 in the isolated `workbench-locked-groups` worktree.

## Changes

- Added `WorkbenchCubit.toggleGroupLock` for center and floating layouts via
  `_mutateLayout` and `SplitLayoutReducer.toggleLock`.
- Added shared `_automaticTargetGroup` selection using focused-group preference,
  nearest unlocked leaf distance, and later-leaf tie breaking.
- Updated `_openIntoLayout` so existing tabs continue to reopen in and focus
  their owning group, including locked groups.
- Updated new-tab routing to use unlocked groups and to call
  `openInNewGroup` when every group is locked, preserving preview and activate
  arguments.
- Added Cubit coverage for locked focused groups, nearest unlocked routing,
  equal-distance tie breaking, locked-owner reopening, and floating-layout
  isolation in the all-locked case.

## Verification

- Red phase: the focused Cubit test command failed to compile because the new
  lock API was absent (plus an initially missing `_s4` fixture, which was
  corrected before implementation verification).
- Green phase: `cd client && dart run tool/run_tests.dart
  test/cubits/workbench/workbench_cubit_test.dart` — 48 tests passed.
- Analyzer: `cd client && flutter analyze --no-fatal-infos
  --no-fatal-warnings` exited successfully; the repository reports existing
  warnings/info diagnostics.

## Scope review

Only `client/lib/cubits/workbench/workbench_cubit.dart`,
`client/test/cubits/workbench/workbench_cubit_test.dart`, and this report were
changed. No UI, localization, sidebar, or floating-window UI work was added.

## Concerns

The full repository test suite is run separately after the task commit. The
analyzer output contains pre-existing repository diagnostics unrelated to this
task.

## Review fixes

- Corrected the locked-owner Cubit test so `_s1` is split away while `_s2`
  remains in the locked owner group; reopening `_s2` now asserts that it stays
  in and focuses that locked owner, with the lock preserved.
- Updated `WorkbenchCubit` class documentation to describe unlocked-focused,
  nearest-leaf, and adjacent-group automatic routing.
- Focused verification after the fixes: `cd client && dart run tool/run_tests.dart
  test/cubits/workbench/workbench_cubit_test.dart` — 48 tests passed.

## Maximized-group visibility fix

- Added Cubit-side automatic-target handling that clears
  `maximizedGroupId` when the destination group differs from the previous
  maximized group, including the all-locked `openInNewGroup` path.
- Automatic placement within the maximized group preserves maximization.
- Added center fallback, center preservation, and floating all-locked sibling
  regression tests.
- Focused verification after the fix: `cd client && dart run tool/run_tests.dart
  test/cubits/workbench/workbench_cubit_test.dart` — 52 tests passed.
- Relevant reducer verification: `cd client && dart run tool/run_tests.dart
  test/cubits/workbench/workbench_split_layout_test.dart` — 62 tests passed.

## Re-review fix: inactive all-locked placement visibility

- Corrected the all-locked automatic-routing path to locate the newly opened
  tab in `nextLayout` and use that sibling group as the visibility destination.
  This clears stale maximization while preserving the reducer's
  `activate: false` focused-group behavior.
- Added a center Cubit regression covering maximization, all groups locked,
  and `openSession(..., activate: false)`. It asserts the new tab is in the
  sibling, the old group remains focused, and `maximizedGroupId` is cleared.
- Focused verification: `cd client && dart run tool/run_tests.dart
  test/cubits/workbench/workbench_cubit_test.dart` — 52 tests passed.
- Relevant reducer verification: `cd client && dart run tool/run_tests.dart
  test/cubits/workbench/workbench_split_layout_test.dart` — 62 tests passed.
