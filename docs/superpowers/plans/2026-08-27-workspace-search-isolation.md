# Workspace Search Isolation Implementation Plan

## Goal

Ensure every workspace search is scoped to sessions owned by that workspace
and that simultaneous workspace search panels do not share debounce state.

## Tasks

1. Add a failing `sessionsForWorkspace` regression test with a stale session ID
   pointing to another workspace; add a failing `SessionDataStore` hydration
   test for rebuilding session IDs.
2. Add a failing debounce regression test covering two independent debouncer
   instances and disposal of a pending operation.
3. Implement the workspace/session join and hydration projection rebuild.
4. Replace the search panel's global debounce key with a panel-owned
   `Debouncer` and dispose it with the widget state.
5. Run focused tests, `flutter analyze --no-fatal-infos --no-fatal-warnings`,
   and `dart run tool/run_tests.dart`; inspect the final diff for unrelated
   changes.

## Test commands

```bash
cd client
flutter test test/utils/session/workspace_sessions_test.dart \
  test/cubits/chat/session_data_store_test.dart \
  test/utils/debounces_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart
```
