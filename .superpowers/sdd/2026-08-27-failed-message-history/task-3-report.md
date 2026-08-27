# Task 3 report

Implemented retry and edit-and-retry for persisted failed session messages.

- Failed bubbles now render `Retry` and `Edit and retry` controls.
- Retry loads the matching persisted failed record, updates that same record to
  `sending`, and routes its text through the existing session `onSubmit`
  delivery callback. The stable message id prevents a duplicate optimistic
  bubble.
- Delivery failure persists the original record back to `failed`; an edited
  retry persists the edited text on the same record id.
- Edit-and-retry loads the stored text into the session composer and preserves
  the failed record identity for the next compose submit.
- Async record lookup is guarded by `HistoryHydrationScope`, so a late lookup
  cannot affect a newly selected seat.

Verification:

- RED: `flutter test test/pages/chat/session_chat_view_failed_message_test.dart`
  failed because `AiHistorySeat.retryPendingUser` did not exist.
- GREEN: `flutter test test/pages/chat/session_chat_view_failed_message_test.dart test/pages/chat/session_history_review_messages_test.dart test/pages/chat/session_chat_view_draft_cache_test.dart`
  passed (20 tests).
- `flutter analyze --no-fatal-infos --no-fatal-warnings` exited 0; it reports
  the repository's existing warning/info backlog (300 issues), with no new
  analyzer errors.
