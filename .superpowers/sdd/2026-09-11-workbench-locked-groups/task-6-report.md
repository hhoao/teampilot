# Task 6 report: persistence compatibility and cross-layer verification

## Scope

Added persistence and cross-layer regression coverage only. Existing Task 1
snapshot compatibility code was left unchanged.

## Coverage added

- Repository save/restore keeps center and floating `lockedGroupIds`
  independent.
- Restore discards unknown lock ids and ids belonging to groups pruned after
  unresolved tabs are removed, independently for center and floating.
- Snapshots missing `lockedGroupIds` restore both surfaces unlocked even when
  the current/restored layouts were pre-locked, preventing a no-op restore
  from satisfying the test.
- Coordinator-level restart/hydration restores lock state on both surfaces.

## Verification

- `dart run tool/run_tests.dart test/repositories/workbench_layout_snapshot_repository_test.dart`
  — 16 tests passed.
- `dart run tool/run_tests.dart test/services/workbench/workbench_layout_persistence_test.dart`
  — 8 tests passed.
- Targeted Task 1–6 regression command from the brief — 186 tests passed.
- `flutter analyze --no-fatal-infos --no-fatal-warnings` — exit 0. The
  repository reports 371 existing warnings/info diagnostics; no new
  production changes were made.
- `git diff --check` — clean.

## Review follow-up evidence

- The legacy compatibility test now saves a snapshot with the field removed,
  pre-locks the receiving layouts, restores, and asserts both lock sets are
  empty.
- The stale-id test now persists live, pruned, and unknown ids on both
  surfaces, rejects the tabs owning the pruned groups, and asserts only each
  surface's surviving live lock remains.
- Focused follow-up runs after these changes: repository 16/16 passed;
  coordinator 8/8 passed.

The requested no-argument full suite was not started, per the explicit task
instruction to avoid it.

## Files changed

- `client/test/repositories/workbench_layout_snapshot_repository_test.dart`
- `client/test/services/workbench/workbench_layout_persistence_test.dart`
