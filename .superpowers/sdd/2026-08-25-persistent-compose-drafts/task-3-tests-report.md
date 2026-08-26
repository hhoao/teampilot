# Task 3 test report — persistent compose drafts

## Added coverage

`client/test/pages/chat/session_chat_view_draft_cache_test.dart` now covers
the submit-result boundary for an existing session:

- a failed `HistoryContinueSubmitResult` retains the saved session draft;
- a successful PTY `HistoryContinueSubmitResult` removes the saved session
  draft.

The local `pumpSession` fixture accepts an injected submit callback. It
installs `InMemoryFilesystem` after `setUpTestAppStorage()` and passes
`routeActive: false` to `SessionChatView`. This keeps persistence in the
widget-test async zone and disables unrelated history live-refresh work.

No production code was modified.

## Landing boundary

No landing submit-result test was added. The existing
`workspace_chat_landing_draft_cache_test.dart` fixture supplies
`WorkspaceChatLanding.onSubmit` as `void Function(String, ...)`; it has no
delivery result to model success versus failure. Exercising that distinction
would require changing the production-facing callback contract or introducing
a new test-only seam, outside this test-only task. Existing landing draft
mount/type/remount coverage remains in its focused suite.

## Verification

```sh
cd client
dart format --set-exit-if-changed test/pages/chat/session_chat_view_draft_cache_test.dart
flutter test test/pages/chat/session_chat_view_draft_cache_test.dart
flutter test test/pages/home_workspace/workspace/workspace_chat_landing_draft_cache_test.dart test/pages/chat/session_chat_view_draft_cache_test.dart test/cubits/chat_cubit_test.dart
```

The session-only command passed 6 tests. The combined focused suite passed 38
tests.
