# Task 6 Report: Fill prompt inputs at session provision

## Status

DONE

## Summary

`workspaceBaseInfoPromptInputs` derives `sshMcpInjected` from `extraMcpServers?[sessionSshMcpServerName]` (seat truth, not the workspace toggle) and remote folders from `profileOf`. Lifecycle and `SessionConnectOrchestrator` pass those inputs into prepare/stage. `ConfigProfileService` copies the named param into every `CliResourceProvisionContext`.

## TDD evidence

### RED

```bash
cd client
dart run tool/run_tests.dart test/services/cli/registry/workspace_base_info_inputs_test.dart
```

Failed to load: `Method not found: 'workspaceBaseInfoPromptInputs'`.

Focused wiring test:

```bash
dart run tool/run_tests.dart test/services/provider/config_profile_service_simple_test.dart --plain-name "prepareSimpleSessionLaunch writes remote prompt when ssh MCP is injected"
```

Failed to load: `No named parameter with the name 'workspaceBaseInfo'`.

### GREEN

```bash
dart run tool/run_tests.dart \
  test/services/cli/registry/workspace_base_info_inputs_test.dart \
  test/services/provider/config_profile_service_simple_test.dart \
  test/services/session/session_lifecycle_service_test.dart \
  test/services/cli/config_profile/opencode_external_directories_test.dart
```

Result: PASS, 34 tests.

Analyze (changed files, `--no-fatal-infos --no-fatal-warnings`): exit 0. Remaining issues are pre-existing (app_shell unawaited return, config_profile null-aware, lifecycle unnecessary import).

## Commit

`feat(session): feed SSH MCP inject state into workspace base-info prompts`

## Concerns

`ensureSessionProfile` now accepts `workspaceBaseInfo` for API consistency but does not construct `CliResourceProvisionContext` (prompts are staged in `stageTeamLaunch` / `applySimpleSessionFilesystem`). Inject is never re-derived from the workspace toggle.
