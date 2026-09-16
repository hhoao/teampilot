# Task 6 Report: Wire ManifestExecutor + homeRoot

## Status

DONE

## Summary

`ManifestExecutor.flush` now builds one ApplyPlan for SSH and local targets. SSH compiles that plan and executes at most one `bash -s` payload followed by one gzip/tar payload; local targets use `WorkPlaneApplier`. Callers pass explicit home/work roots, and ancestor-only staged `ensureDir` operations are ignored because the declared work root already exists.

## TDD evidence

### RED

```bash
cd client
dart run tool/run_tests.dart test/services/launch/manifest_executor_ssh_test.dart
```

Failed at compile time because `flush` did not accept `homeRoot`. After the initial implementation, the local staging tests failed with `path cannot be projected: /tmp`, exposing ancestor `ensureDir` entries outside the declared work root.

### GREEN

```bash
dart run tool/run_tests.dart \
  test/services/launch/manifest_executor_ssh_test.dart \
  test/services/launch/manifest_filesystem_test.dart \
  test/services/launch/launch_manifest_staging_test.dart \
  test/services/launch/work_path_projector_test.dart \
  test/services/launch/work_plane_applier_test.dart \
  test/services/launch/apply_plan_ssh_compiler_test.dart
```

Result: PASS, 42 tests.

Additional caller test:

```bash
dart run tool/run_tests.dart \
  test/services/session/team_generation_session_resources_test.dart
```

Result: PASS, 3 tests.

Focused analysis:

```bash
dart analyze lib/services/launch
```

Result: PASS, no issues.

Repository-wide `flutter analyze --no-fatal-infos --no-fatal-warnings` was also attempted. It remains non-zero because of a pre-existing undefined `launchSecurityPolicy` named parameter in `remote_ssh_launch_constraints_test.dart`; no diagnostics were reported for Task 6 files after removing one unnecessary import.

## Commit

`feat(launch): flush manifests through apply plans`

## Concerns

No Task 6 blocker. The unrelated repository-wide analyzer error remains.
