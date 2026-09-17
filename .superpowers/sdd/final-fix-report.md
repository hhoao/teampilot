# Whole-branch review fixes: feat/resource-scheduler-packages

**Status:** complete  
**Branch:** `feat/resource-scheduler-packages`  
**Worktree:** `/home/hhoa/git/hhoa/teampilot/.worktrees/feat-resource-scheduler-packages`  
**Pushed:** no

## Fixes

1. **SessionInitException hides the cause** — `toString()` now includes `message` and `cause`. `_stage` wraps with `message: '$e'` so connect UI still surfaces `path cannot be projected` / `path escapes workRoot`. New scheduler test: projector failure `toString()` contains the original error text.
2. **CI/analyze gate** — `.github/workflows/client-verify.yml` runs `dart analyze` + `dart test` for `teampilot_fs`, `teampilot_apply`, and `teampilot_scheduler` (same job, after `teampilot_search`). `docs/DEVELOPMENT.md` tests section already listed package tests; existing bullet now names the three packages.
3. **Orchestrator connect cutover** — unit test `prepareSimpleConnect` stages a write, applies via `SessionScheduler`, lands `/work-tp/hello.txt` on workFs, and asserts `ManifestExecutor.flush` is unused. Did not rewrite `SessionLifecycleService`; used existing constructor injection + fakes.

Minors left as requested (duplicate WorkspaceCliCache, LockPool, empty argv, unused sshProfileId, debugBuildApplyScript, shim barrel width, lstat, DTO equality, ResourceContributor unused, sessionConfigDir unused).

## Covering tests (re-run after fixes)

### `cd client/packages/teampilot_fs && dart analyze && dart test`

```
Analyzing teampilot_fs...
No issues found!
00:00 +13: All tests passed!
```

### `cd client/packages/teampilot_apply && dart analyze && dart test`

```
Analyzing teampilot_apply...
No issues found!
00:00 +11: All tests passed!
```

### `cd client/packages/teampilot_scheduler && dart analyze && dart test`

```
Analyzing teampilot_scheduler...
No issues found!
00:00 +26: All tests passed!
```

Includes `projector failure SessionInitException.toString contains original error`.

### Client analyze (touched orchestrator paths)

```
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/services/launch/session_connect_orchestrator.dart \
  test/services/launch/session_connect_orchestrator_test.dart
```

```
Analyzing 2 items...
No issues found! (ran in 5.7s)
```

### Client covering tests (not the full suite)

```
cd client
dart run tool/run_tests.dart \
  test/services/launch/session_connect_orchestrator_test.dart \
  test/services/launch/delegating_session_cli_plugin_test.dart \
  test/services/launch/session_init_request_mapper_test.dart
```

```
00:00 +0: prepareSimpleConnect applies staged writes via SessionScheduler, not ManifestExecutor.flush
00:00 +1: SessionScheduler.init applies delegated contribute writes
00:00 +2: maps LaunchSecurityPolicy.fullAccess to SessionSecurityPolicy.fullAccess
00:00 +3: maps LaunchSecurityPolicy fields onto SessionSecurityPolicy
00:00 +4: All tests passed!
```

Full client suite **not** run (review instruction).
