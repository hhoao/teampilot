# Task 4 report: floating-window lock control placement

## Status

Implemented and committed as `feat(workbench): add floating group lock controls`.

## Changes

- Added the shared `WorkbenchGroupLockButton` to every visible floating split
  group header, immediately after that group’s tab strip.
- Added the focused group lock button to the outer floating title bar only for
  single-group or narrow rendering, after `+` and before window chrome.
- Wide multi-group title bars intentionally receive no global lock button.
- Wired both locations to the live floating layout lock state and
  `WorkbenchCubit.toggleGroupLock(..., floating: true)`.
- Added widget coverage for per-pane controls and ownership, title-bar order,
  narrow rendering and focused-group toggling, and the absence of a wide
  global control.

## Verification

Focused command:

```text
cd client && dart run tool/run_tests.dart test/pages/floating_workspace/floating_split_test.dart
```

Result: **PASS — 8 tests passed**, including narrow-mode title-bar placement
and focused-group lock toggling. The narrow test identifies the outer lock by
matching its title-bar-row Y coordinate to both `+` and window chrome before
checking X order and tapping it.

`flutter analyze --no-fatal-infos --no-fatal-warnings` also exited successfully;
the repository reports pre-existing analyzer warnings/info diagnostics.

The no-argument full-suite run was started before the task instruction changed
and was intentionally stopped by the user. It is not used as a verification
requirement for this task.

## Scope check

No sidebar files or unrelated production files were modified.
