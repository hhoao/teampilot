# Final important-finding fix

## Important 1

- PTY follow-up success still calls `onSessionHistoryStale(sessionId)`.
- It now also force-soft-reloads the pod-owned `HistoryStore` member seat used
  by `SessionChatView`.
- The cubit regression test records and asserts that pod seat reload request.

## Important 2

Deferred as a product decision: failed PTY drain still marks History pending
failed while retaining the follow-up queue head, leaving both retry paths.

## Verification

Command:

```text
cd client
dart format lib/cubits/chat_cubit.dart test/cubits/chat/follow_up_deliver_history_ux_test.dart
flutter test test/cubits/chat/follow_up_deliver_history_ux_test.dart
```

Output:

```text
Formatted 2 files (0 changed) in 0.04 seconds.
00:00 +3: All tests passed!
```

Repository checks:

```text
flutter analyze --no-fatal-infos --no-fatal-warnings
304 pre-existing warnings/infos; command passed.

dart run tool/run_tests.dart
Reached 2826 passing tests with no reported test failure, then exited 1 without
a final summary during terminal_session_test.dart.

dart run tool/run_tests.dart --reporter compact
Reached 1709 passing tests with no reported test failure, then stopped making
progress; terminated after 8m48s.
```
