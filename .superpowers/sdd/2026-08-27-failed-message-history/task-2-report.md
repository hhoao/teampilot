# Task 2 report

Implemented persisted optimistic delivery bubbles.

- Persists the exact pending bubble before the compose field is cleared.
- Hydrates sending and failed records when a history seat binds, scoped by workspace/session.
- Keeps a failed bubble visible instead of rolling it back; the existing thread renders `Sending` or `Failed` below that bubble.
- Removes persisted optimistic state once the matching CLI user turn confirms, preventing a restored duplicate after restart.

Verification:

- RED: `flutter test test/pages/chat/session_chat_view_failed_message_test.dart` (missing persistence APIs).
- GREEN: `flutter test test/pages/chat/session_chat_view_draft_cache_test.dart test/pages/chat/session_chat_view_failed_message_test.dart test/pages/chat/session_history_review_messages_test.dart`
- `flutter analyze --no-fatal-infos --no-fatal-warnings` for all touched implementation/tests.

## Round 1 review fixes

- History hydration now waits for the initial transcript load to establish its CLI user-turn baseline; restored records can no longer be consumed by pre-existing transcript turns.
- FIFO transcript confirmation skips persisted `failed` records. Only pending/sending records are eligible for confirmation and persisted-record cleanup.
- Added focused seat tests for restoring alongside existing user history and for preserving a failed record after a later CLI user turn.
