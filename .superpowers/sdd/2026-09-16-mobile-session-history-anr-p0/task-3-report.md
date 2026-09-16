# Task 3 implementation report

## Scope

Implemented Task 3 of the mobile session-history ANR P0 plan. Tasks 4 and 5
were not implemented.

## Implementation

- Page-reader misses now publish an incomplete result immediately, retaining
  any previously non-empty messages.
- Full indexing is registered through a single-flight background future and
  runs through the existing full-index path without synchronously parsing a
  large transcript in the caller isolate.
- Completed background indexes retain the cache token and are consumed by the
  existing seat hydration path, preserving no-blank behavior and incremental
  message identity.
- Existing injected storage/filesystem resolution and public behavior for
  capabilities without page readers remain intact.
- No transcript or message content was added to diagnostics.

## Verification

- Focused tests, run through the required wrapper:

  `cd client && dart run tool/run_tests.dart test/services/session/ai_history_loader_test.dart test/cubits/ai_history_seat_no_blank_test.dart`

  Result: `00:01 +63: All tests passed!`

- Scoped analyzer/checks:

  `flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/session/ai_history_loader.dart lib/cubits/ai_history_seat.dart test/services/session/ai_history_loader_test.dart test/cubits/ai_history_seat_no_blank_test.dart`

  Result: exit 0. One pre-existing deprecation info remains in the loader
  test (`dispose`, recommending `close()`). `git diff --check` passed.

## Concerns

- The pre-existing analyzer deprecation info was outside the Task 3 behavior
  change and was left unchanged.
- The worktree had a pre-existing modified `resources` submodule; it was not
  staged or modified by Task 3.
