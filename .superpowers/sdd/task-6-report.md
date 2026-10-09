# Task 6 Report: Persist acp on create

## TDD Evidence
- RED: `dart run tool/run_tests.dart test/services/chat/launch/session_provisional_builder_test.dart test/repositories/session_repository_acp_test.dart` -> both files failed to compile (`No named parameter with the name 'acp'`).
- GREEN: same two files + `session_launch_coordinator_test.dart` -> 18 tests, "All tests passed!". `session_repository_working_dir_test.dart` also passed.
- `flutter analyze` on touched dirs: no errors/warnings (only pre-existing infos).

## Files changed
- `client/lib/services/chat/session/session_create_request.dart` — `bool acp = false`
- `client/lib/services/chat/session/session_persist_params.dart` — `bool acp = false`
- `client/lib/services/chat/launch/session/session_launch_coordinator.dart` — `request.acp` -> provisional + persistParams
- `client/lib/services/chat/launch/session/session_provisional_builder.dart` — `bool? acp`; resolved acp
- `client/lib/services/chat/launch/session_launch_service.dart` — `acp: params.acp`
- `client/lib/repositories/session_repository.dart` — `createSession(acp)`, `resolvedAcp = trimmedTeam.isEmpty && (acp || cli == CliTool.gemini)` passed explicitly
- New tests: `client/test/services/chat/launch/session_provisional_builder_test.dart`, `client/test/repositories/session_repository_acp_test.dart`

## Self-review
- Covered: personal Claude acp true -> true; default -> false; Gemini personal -> true even with acp false; team -> false even with acp true (provisional + repository).
- Provisional formula: `trimmedTeam.isEmpty && isPersonal && (acp ?? false || (identity?.cli ?? cli) == gemini)`.
- No `if (cli ==` added in services/acp/. No print. attachAcpRuntime and UI untouched.

## Concerns
- Repository tests use the existing tmp-dir + `fakeHomeStorage()` pattern (as in other session_repository tests), not `setUpTestAppStorage`.
- `SessionDataStore.createSession` wrapper (not in brief) does not forward acp; no caller yet.
