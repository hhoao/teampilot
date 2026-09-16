# P0 Critical Fix Report

## Fix

- Cold background full-index bootstrap now skips the unseeded
  `AiTranscriptTailReader` path. Large located bundles go through the injected
  `HistoryParseExecutor`; production uses `HistoryParseWorker` and its
  `TransferableTypedData` transport.
- Large worker failures return a safe incomplete result instead of falling back
  to caller-isolate transcript decoding.
- Background results are generation-guarded across invalidation, including
  worker index snapshot import and the attachment-preparation-to-cache-commit
  boundary. Failed full-index futures are removed only when the failed future
  is still the identical cache entry.
- Existing injected filesystem/SSH context flow is preserved.

## Focused verification

The new regression fails before the guard and passes after it:

```text
dart run tool/run_tests.dart test/services/session/ai_history_loader_test.dart \
  --plain-name="invalidation during attachment preparation cannot overwrite a newer full index"
```

Before the production guard: exit code 1 (`fresh-message` was overwritten by
`stale-message`). After the guard: exit code 0, 1 test passed.

The five exact P0 loader regressions passed:

1. `background full bootstrap skips tail decode and returns incomplete on worker failure`
2. `invalidation prevents a stale background full index from repopulating the cache`
3. `invalidation prevents a stale background worker snapshot from being imported`
4. `failed background full index flight is cleared so the next load retries`
5. `invalidation during attachment preparation cannot overwrite a newer full index`

The complete focused `ai_history_loader_test.dart` file passed: 54 tests.

Exact command:

```text
cd client && dart run tool/run_tests.dart \
  test/services/session/ai_history_loader_test.dart
```

Exit code 0; all 54 tests passed.

## Analyzer

Targeted analyzer:

```text
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/services/session/ai_history_loader.dart \
  test/services/session/ai_history_loader_test.dart
```

Exit code 0. It reported one existing deprecation info for test cleanup at
`test/services/session/ai_history_loader_test.dart:4060` and no errors.

Repository-wide analyzer was run as required but exited 1 on unrelated existing
errors, including `test/pages/home_workspace/workspace/workspace_landing_worktree_refresher_test.dart:38`
and `test/services/session/remote_ssh_launch_constraints_test.dart:594`.

## Concerns

- The broad test suite was not run in this follow-up; this report covers the
  focused loader regression and targeted analyzer only.
- Android/device ANR validation was not available in this run.
- The pre-existing dirty `resources` submodule was not staged or changed.
