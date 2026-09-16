# P0 Critical Fix Report

## Fix

- Cold background full-index bootstrap now skips the unseeded
  `AiTranscriptTailReader` path. Large located bundles go through the injected
  `HistoryParseExecutor`; production uses `HistoryParseWorker` and its
  `TransferableTypedData` transport.
- Large worker failures return a safe incomplete result instead of falling back
  to caller-isolate transcript decoding.
- Background results are generation-guarded across invalidation, including
  worker index snapshot import. Failed full-index futures are removed only when
  the failed future is still the identical cache entry.
- Existing injected filesystem/SSH context flow is preserved.

## Focused verification

All four exact `ai_history_loader_test.dart` regressions passed:

1. `background full bootstrap skips tail decode and returns incomplete on worker failure`
2. `invalidation prevents a stale background full index from repopulating the cache`
3. `invalidation prevents a stale background worker snapshot from being imported`
4. `failed background full index flight is cleared so the next load retries`

The complete focused `ai_history_loader_test.dart` file also passed: 53 tests.
The related worker/page/adapter focused set passed: 51 tests.

## Analyzer

Targeted analyzer:

```text
flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/services/session/ai_history_loader.dart \
  test/services/session/ai_history_loader_test.dart \
  test/support/fake_ai_history_registry.dart
```

Exit code 0. It reported one existing deprecation info for test cleanup and no
errors in the touched files.

Repository-wide analyzer was run as required but exited 1 on unrelated existing
errors, including `test/pages/home_workspace/workspace/workspace_landing_worktree_refresher_test.dart:38`
and `test/services/session/remote_ssh_launch_constraints_test.dart:594`.

## Concerns

- The broad test suite was intentionally stopped at the user's request; it is
  not a P0 verification result. Before interruption it had one unrelated
  failure in `test/repositories/session_list_load_test.dart`.
- Android/device ANR validation was not available in this run.
- The pre-existing dirty `resources` submodule was not staged or changed.
