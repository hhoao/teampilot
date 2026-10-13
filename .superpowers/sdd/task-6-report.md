# Task 6 Report: openSession / start accept mcpServers

## Status
**Complete**

## Commits
- `39cc86b13` — Pass MCP servers through ACP session/new.

Landed on `fa7c8a0cd` (includes `c2f298b24` plus later merges already on this branch).

## TDD
- RED: helper file missing (`acpMcpServersFromExtra` undefined) and `No named parameter with the name 'mcpServers'` on `openSession` and `start`.
- GREEN: `cd client && RUN_TESTS_ALLOW_PUB_SOURCE_MISMATCH=1 dart run tool/run_tests.dart test/services/acp/` — 105 tests, all passed.
- `flutter analyze` on touched files: no new issues. Pre-existing `unused_import` of `ai_message_core` in `chat_tab_acp_runtimes_test.dart` left as-is.

## Test summary
- `acp_mcp_servers_test.dart`: stdio + http map (command, args, url, header map); empty extra; skip entries with neither command nor url; headers from a `{name, value}` list.
- `acp_session_test.dart`: omitted `mcpServers` stays empty; `McpServerStdio(name: teammate-bus, command: /bin/bridge, args: [--bus-url, http://x])` is recorded on `session/new`.
- `acp_session_runtime_test.dart`: omitted list stays empty; `start(mcpServers:)` forwards the same stdio server.

## Self-review
- `openSession` and `AcpSessionRuntimeApi.start` / `AcpSessionRuntime.start` take `List<acpd.McpServer> mcpServers = const []` and pass it through to `NewSessionRequest`.
- `clientRequests` on the runtime API is unchanged.
- Personal callers (including `AcpChatRuntimeCubit.start`) still omit the list.
- Mixed attach is not wired.
- Every `AcpSessionRuntimeApi` implementer/fake gained the named parameter so the interface still type-checks. Specs and `pubspec.lock` were not committed.

## Concerns
- Stdio `env` dicts are not copied onto `McpServerStdio`. Team-bus and catalog extra entries used by later tasks are command/args or http url/headers only.
- Attach fakes accept `mcpServers` but do not record it. Task 8 adds that assertion.
