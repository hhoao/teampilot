# CLI Launch Argument Capabilities Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

Goal: Replace monolithic per-CLI launch argument builders with composable capability-provided argument contributions, including first-class multi-directory support and a normalized security policy model.

Architecture: CliLaunchContext is the semantic request. Capabilities in a CliToolDefinition may implement CliLaunchArgProvider and return immutable CliLaunchArgContribution values. CliLaunchArgAssembler collects, validates, orders, and flattens those contributions; PTY, SSH, external-terminal, and preview paths all use it. CliSessionCapability is reduced to lifecycle/configuration responsibilities and no longer builds argv.

Tech Stack: Dart, Flutter, flutter_test, existing CliToolRegistry, CliToolDefinition, ShellLaunchSpec, LaunchCommandBuilder, and session launch services.

## Global Constraints

- Do not retain CliToolAdapter.buildArguments() or compatibility wrappers after migration.
- Do not retain dangerouslySkipPermissions as the security-policy source of truth.
- Every startup argument must be emitted by a named launch capability and assembled by CliLaunchArgAssembler.
- Unsupported permission, workspace, or team-mode combinations fail explicitly; they are never silently dropped.
- Raw team.extraArgs and member.extraArgs are emitted last by UserExtraArgsCapability.
- Process cwd, SSH target selection, filesystem provisioning, and config-file materialization remain outside argv providers.
- Use AppLogger instead of print, AppStorage for paths, flutter_bloc for state, and the existing l10n ARB files for user-facing copy.
- Use test-first development for every behavior change: failing test, focused red run, minimal implementation, focused green run.
- Existing unrelated worktree changes must remain untouched.

## File map

New shared launch files:

- client/lib/services/cli/registry/launch/cli_launch_context.dart
- client/lib/services/cli/registry/launch/cli_launch_arg_provider.dart
- client/lib/services/cli/registry/launch/cli_launch_arg_contribution.dart
- client/lib/services/cli/registry/launch/cli_launch_arg_assembler.dart
- client/lib/services/cli/registry/launch/cli_launch_capability_error.dart
- client/lib/models/launch_security_policy.dart
- client/lib/services/cli/registry/launch/session_selection_arg_provider.dart
- client/lib/services/cli/registry/launch/workspace_access_arg_provider.dart
- client/lib/services/cli/registry/launch/user_extra_args_provider.dart

New per-CLI launch capability files:

- client/lib/services/cli/claude/capabilities/session_selection_launch.dart
- client/lib/services/cli/claude/capabilities/workspace_access_launch.dart
- client/lib/services/cli/claude/capabilities/model_launch.dart
- client/lib/services/cli/claude/capabilities/permission_launch.dart
- client/lib/services/cli/claude/capabilities/prompt_launch.dart
- client/lib/services/cli/flashskyai/capabilities/session_selection_launch.dart
- client/lib/services/cli/flashskyai/capabilities/workspace_access_launch.dart
- client/lib/services/cli/flashskyai/capabilities/model_launch.dart
- client/lib/services/cli/flashskyai/capabilities/permission_launch.dart
- client/lib/services/cli/flashskyai/capabilities/prompt_launch.dart
- client/lib/services/cli/codex/capabilities/session_selection_launch.dart
- client/lib/services/cli/codex/capabilities/workspace_access_launch.dart
- client/lib/services/cli/codex/capabilities/model_launch.dart
- client/lib/services/cli/codex/capabilities/permission_launch.dart
- client/lib/services/cli/cursor/capabilities/session_selection_launch.dart
- client/lib/services/cli/cursor/capabilities/workspace_access_launch.dart
- client/lib/services/cli/cursor/capabilities/model_launch.dart
- client/lib/services/cli/cursor/capabilities/permission_launch.dart
- client/lib/services/cli/opencode/capabilities/session_selection_launch.dart
- client/lib/services/cli/opencode/capabilities/model_launch.dart
- client/lib/services/cli/opencode/capabilities/agent_launch.dart
- client/lib/services/cli/opencode/capabilities/user_extra_args_launch.dart

Existing files to modify/remove:

- Modify client/lib/services/cli/registry/cli_tool_registry.dart, cli_tool_definition.dart, and capabilities/cli_session_capability.dart.
- Modify client/lib/services/cli/claude/claude_tool.dart, client/lib/services/cli/flashskyai/flashskyai_tool.dart, client/lib/services/cli/codex/codex_tool.dart, client/lib/services/cli/cursor/cursor_tool.dart, and client/lib/services/cli/opencode/opencode_tool.dart.
- Modify client/lib/services/cli/claude/capabilities/team_behavior.dart, client/lib/services/cli/flashskyai/capabilities/team_behavior.dart, client/lib/services/cli/codex/capabilities/team_behavior.dart, client/lib/services/cli/cursor/capabilities/team_behavior.dart, and client/lib/services/cli/opencode/capabilities/team_behavior.dart.
- Modify client/lib/services/session/launch_command_builder.dart, shell_launch_spec.dart, and session_lifecycle_service.dart.
- Modify client/lib/services/launch/session_shell_connector.dart and session_connect_orchestrator.dart.
- Modify permission models and consumers listed in Task 3 and Task 9.
- Delete client/lib/services/cli/cli_tool_adapter.dart, client/lib/services/cli/claude/capabilities/launch_args.dart, client/lib/services/cli/flashskyai/capabilities/launch_args.dart, client/lib/services/cli/codex/capabilities/launch_args.dart, client/lib/services/cli/cursor/capabilities/launch_args.dart, and client/lib/services/cli/opencode/capabilities/launch_args.dart after migration.

---

### Task 1: Introduce launch contribution primitives and registry collection

Files:

- Create client/lib/services/cli/registry/launch/cli_launch_arg_contribution.dart
- Create client/lib/services/cli/registry/launch/cli_launch_arg_provider.dart
- Create client/lib/services/cli/registry/launch/cli_launch_capability_error.dart
- Create client/lib/services/cli/registry/launch/cli_launch_arg_assembler.dart
- Modify client/lib/services/cli/registry/cli_tool_registry.dart
- Modify client/lib/services/cli/registry/cli_tool_definition.dart
- Test client/test/services/cli/registry/launch/cli_launch_arg_assembler_test.dart
- Test client/test/services/cli/registry/cli_tool_registry_test.dart

Interfaces:

- CliLaunchArgProvider.buildLaunchArgs(CliLaunchContext) returns Iterable<CliLaunchArgContribution>.
- CliLaunchArgContribution contains key, LaunchArgPhase, args, and optional exclusiveGroup.
- CliLaunchArgAssembler.assemble(CliToolDefinition, CliLaunchContext) returns List<String>.
- CliToolRegistry.capabilitiesOf<T extends CliCapability>(CliTool) returns every matching capability in definition order.

- [ ] Step 1: Write failing assembler tests for phase ordering, stable provider ordering, duplicate keys, exclusive groups, empty contributions, and token flattening.

    test('assembles contributions by phase and stable provider order', () {
      final tool = FakeCliTool([
        FakeLaunchProvider(const CliLaunchArgContribution(
          key: 'model',
          phase: LaunchArgPhase.model,
          args: ['--model', 'x'],
        )),
        FakeLaunchProvider(const CliLaunchArgContribution(
          key: 'session',
          phase: LaunchArgPhase.session,
          args: ['--resume', 's'],
        )),
      ]);
      expect(const CliLaunchArgAssembler().assemble(tool, context), [
        '--resume', 's', '--model', 'x',
      ]);
    });

- [ ] Step 2: Run the focused test and verify it fails because the new types do not exist.

    cd client && flutter test test/services/cli/registry/launch/cli_launch_arg_assembler_test.dart

    Expected: FAIL with missing contribution/provider/assembler types.

- [ ] Step 3: Implement the contribution value, provider interface, typed exception, and assembler. The assembler collects providers from tool.capabilities, rejects duplicate keys and exclusive-group collisions, sorts by phase.index then original provider index, and flattens tokens without shell quoting.
- [ ] Step 4: Add capabilitiesOf<T>() and tests proving all matching providers are returned in definition order. Keep capability<T>() for existing single-capability consumers.
- [ ] Step 5: Run the focused tests.

    cd client && flutter test test/services/cli/registry/launch/cli_launch_arg_assembler_test.dart test/services/cli/registry/cli_tool_registry_test.dart

    Expected: PASS.

- [ ] Step 6: Commit the foundation.

    git add client/lib/services/cli/registry/launch client/lib/services/cli/registry/cli_tool_registry.dart client/test/services/cli/registry/launch client/test/services/cli/registry/cli_tool_registry_test.dart
    git commit -m "refactor(cli): add composable launch argument contributions"

### Task 2: Move launch context out of the deleted adapter and split session lifecycle

Files:

- Create client/lib/services/cli/registry/launch/cli_launch_context.dart
- Modify client/lib/services/cli/registry/capabilities/cli_session_capability.dart
- Modify client/lib/services/cli/registry/capabilities/noop_cli_session_capability.dart
- Modify client/lib/services/cli/registry/cli_tool_registry.dart
- Modify client/lib/services/cli/cli_tool_adapter.dart imports in client/lib/services/session/launch_command_builder.dart, client/lib/services/session/shell_launch_spec.dart, client/lib/services/cli/claude/capabilities/launch_args.dart, client/lib/services/cli/flashskyai/capabilities/launch_args.dart, client/lib/services/cli/codex/capabilities/launch_args.dart, client/lib/services/cli/cursor/capabilities/launch_args.dart, client/lib/services/cli/opencode/capabilities/launch_args.dart, client/lib/services/cli/claude/capabilities/session.dart, client/lib/services/cli/flashskyai/capabilities/session.dart, client/lib/services/cli/codex/capabilities/session.dart, client/lib/services/cli/cursor/capabilities/session_lifecycle.dart, and client/lib/services/cli/opencode/capabilities/session.dart.
- Test client/test/services/cli/registry/launch/cli_launch_context_test.dart
- Test client/test/services/cli/registry/noop_cli_session_capability_test.dart

Interfaces:

- CliLaunchContext retains team, member, sessionTeam, workingDirectory, additionalDirectories, fixedSessionId, resumeSessionId, settingsPath, appendSystemPromptFile, useWslPaths, nativeAgentTeam, and the resolved LaunchSecurityPolicy.
- CliSessionCapability retains lifecycle, gate, post-flush, and sessionConfigDir methods but removes buildArguments.
- CliLaunchArgAssembler receives CliToolDefinition and CliLaunchContext, never a session capability.

- [ ] Step 1: Write failing context tests for copyWith, teamName, memberCliId, usesNativeAgentTeam, and WSL path normalization.
- [ ] Step 2: Run the focused context test and verify it fails because context is still located in the old adapter file.

    cd client && flutter test test/services/cli/registry/launch/cli_launch_context_test.dart

    Expected: FAIL with the new import/type unavailable.

- [ ] Step 3: Move CliLaunchContext and normalizePathForCli/WSL conversion helpers into focused launch files. Do not move raw extra-argument parsing into the context.
- [ ] Step 4: Remove buildArguments from CliSessionCapability and DefaultCliConfigLayout; update every session implementation to contain only lifecycle/config layout methods.
- [ ] Step 5: Update imports and run the focused session/registry tests.

    cd client && flutter test test/services/cli/registry/launch/cli_launch_context_test.dart test/services/cli/registry/noop_cli_session_capability_test.dart test/services/cli/registry/cli_tool_registry_test.dart

    Expected: PASS with no test references to CliToolAdapter or CliSessionCapability.buildArguments.

- [ ] Step 6: Commit the context/lifecycle split.

    git add client/lib/services/cli/registry/launch/cli_launch_context.dart client/lib/services/cli/registry/capabilities client/lib/services/cli/registry/cli_tool_registry.dart client/test/services/cli/registry
    git commit -m "refactor(cli): separate launch context from session lifecycle"

### Task 3: Replace the boolean permission model with normalized security policy

Files:

- Create client/lib/models/launch_security_policy.dart
- Modify client/lib/models/team_config.dart
- Modify client/lib/models/workspace_agent_config.dart
- Modify client/lib/models/automation.dart
- Modify client/lib/models/landing_launch_context.dart
- Modify client/lib/models/session_continue_overrides.dart
- Modify client/lib/services/session/session_continue_overrides_apply.dart
- Modify client/lib/services/session/remote_ssh_launch_constraints.dart
- Modify client/lib/services/automation/automation_dispatcher.dart
- Modify client/lib/services/launch/session_shell_connector.dart
- Modify client/lib/cubits/chat_cubit.dart
- Modify client/lib/cubits/chat/session_continue_overrides_controller.dart
- Modify client/lib/cubits/team/launch_profile_selectors.dart, client/lib/pages/automations/automation_editor_dialog.dart, client/lib/pages/automations/automation_editor_form_body.dart, client/lib/pages/automations/automation_editor_launch_section.dart, client/lib/pages/chat/session_chat_compose_section.dart, client/lib/pages/home_workspace/workspace/unbound_compose_body.dart, client/lib/pages/home_workspace/workspace/workspace_landing_team_settings_dialog.dart, client/lib/pages/home_workspace/workspace/workspace_session_actions.dart, client/lib/pages/team_config/team_config_member_section.dart, client/lib/services/home_workspace/landing_prefs_store.dart, client/lib/services/cli/codex/capabilities/provider.dart, client/lib/services/cli/codex/provider/codex_managed_hook_overlay.dart, client/lib/services/team_bus/mcp/toolkit/teammate_bus_tool_format.dart, client/lib/services/team_bus/teammate_roster_profile.dart, client/lib/utils/workspace/landing_draft_resolver.dart, client/lib/widgets/compose/compose_chrome.dart, client/lib/widgets/compose/compose_permission_chip.dart, and client/lib/widgets/compose/workspace_compose_card.dart.
- Test client/test/models/launch_security_policy_test.dart
- Test client/test/models/team_config_test.dart
- Test client/test/models/automation_test.dart
- Test client/test/services/session/session_continue_overrides_apply_test.dart
- Test client/test/services/session/remote_ssh_launch_constraints_test.dart

Interfaces:

- LaunchApprovalPolicy: cliDefault, ask, autoApprove, never.
- LaunchSandboxPolicy: cliDefault, readOnly, workspaceWrite, fullAccess.
- LaunchHookTrustPolicy: cliDefault, trustedOnly, bypass.
- LaunchSecurityPolicy is immutable, has JSON codec, copyWith, equality, and requiresDangerousExecution.
- Replace TeamMemberConfig.dangerouslySkipPermissions, automation booleans, and continue-override booleans with LaunchSecurityPolicy.

- [ ] Step 1: Write policy tests for JSON round-trip, equality, default policy, and dangerous-policy detection.

    test('full access policy requires dangerous execution', () {
      const policy = LaunchSecurityPolicy(
        approval: LaunchApprovalPolicy.never,
        sandbox: LaunchSandboxPolicy.fullAccess,
        hookTrust: LaunchHookTrustPolicy.bypass,
      );
      expect(policy.requiresDangerousExecution, isTrue);
    });

- [ ] Step 2: Run the policy test and verify it fails because the model and serialized fields are absent.

    cd client && flutter test test/models/launch_security_policy_test.dart

    Expected: FAIL.

- [ ] Step 3: Implement the policy model and replace serialized fields with a launchSecurityPolicy JSON object. Do not decode or write dangerouslySkipPermissions.
- [ ] Step 4: Update session-continue resolution so member/session overrides merge complete policy values field-by-field with the launch profile policy as base.
- [ ] Step 5: Update automation, landing, remote SSH, and chat launch paths to carry the policy. SSH constraints must reject unsupported full-access requests with the typed launch error or explicitly return a warning plus transformed policy.
- [ ] Step 6: Run the affected model/session tests.

    cd client && flutter test test/models/launch_security_policy_test.dart test/models/team_config_test.dart test/models/automation_test.dart test/services/session/session_continue_overrides_apply_test.dart test/services/session/remote_ssh_launch_constraints_test.dart test/cubits/chat_cubit_continue_overrides_test.dart

    Expected: PASS with no production-code references to dangerouslySkipPermissions.

- [ ] Step 7: Commit the semantic permission model.

    git add client/lib/models client/lib/services/session client/lib/services/automation client/lib/services/launch client/lib/cubits/chat_cubit.dart client/lib/cubits/chat/session_continue_overrides_controller.dart client/test/models client/test/services/session client/test/cubits/chat_cubit_continue_overrides_test.dart
    git commit -m "refactor(security): replace boolean launch permissions with policy"

### Task 4: Implement shared session, workspace, and user-argument providers

Files:

- Create client/lib/services/cli/registry/launch/session_selection_arg_provider.dart
- Create client/lib/services/cli/registry/launch/workspace_access_arg_provider.dart
- Create client/lib/services/cli/registry/launch/user_extra_args_provider.dart
- Modify client/lib/services/cli/registry/launch/cli_launch_arg_assembler.dart
- Modify client/lib/services/cli/registry/launch/cli_launch_context.dart
- Test client/test/services/cli/registry/launch/session_selection_arg_provider_test.dart
- Test client/test/services/cli/registry/launch/workspace_access_arg_provider_test.dart
- Test client/test/services/cli/registry/launch/user_extra_args_provider_test.dart

Interfaces:

- SessionSelectionArgProvider defines the semantic session-selection contract; each CLI supplies its encoding.
- WorkspaceAccessArgProvider defines primary cwd/additional-directory inputs and path normalization.
- UserExtraArgsProvider uses splitArgs(String) and emits team then member raw args in LaunchArgPhase.user.

- [ ] Step 1: Write failing tests for blank filtering, repeated --add-dir pairs, WSL conversion, and exact team/member extra-arg ordering.
- [ ] Step 2: Run the focused tests and verify missing-provider failures.

    cd client && flutter test test/services/cli/registry/launch/session_selection_arg_provider_test.dart test/services/cli/registry/launch/workspace_access_arg_provider_test.dart test/services/cli/registry/launch/user_extra_args_provider_test.dart

    Expected: FAIL because the shared providers do not exist.

- [ ] Step 3: Implement the contracts and move splitArgs plus path normalization into the launch namespace. Preserve token boundaries; no shell quoting is introduced here.
- [ ] Step 4: Run the focused tests and confirm all shared provider behavior passes.
- [ ] Step 5: Commit the shared provider layer.

    git add client/lib/services/cli/registry/launch client/test/services/cli/registry/launch
    git commit -m "refactor(cli): add shared launch argument provider contracts"

### Task 5: Migrate Claude and FlashskyAI capabilities

Files:

- Create/modify client/lib/services/cli/claude/capabilities/session_selection_launch.dart, client/lib/services/cli/claude/capabilities/workspace_access_launch.dart, client/lib/services/cli/claude/capabilities/model_launch.dart, client/lib/services/cli/claude/capabilities/permission_launch.dart, and client/lib/services/cli/claude/capabilities/prompt_launch.dart.
- Create/modify client/lib/services/cli/flashskyai/capabilities/session_selection_launch.dart, client/lib/services/cli/flashskyai/capabilities/workspace_access_launch.dart, client/lib/services/cli/flashskyai/capabilities/model_launch.dart, client/lib/services/cli/flashskyai/capabilities/permission_launch.dart, and client/lib/services/cli/flashskyai/capabilities/prompt_launch.dart.
- Modify client/lib/services/cli/claude/capabilities/team_behavior.dart
- Modify client/lib/services/cli/flashskyai/capabilities/team_behavior.dart
- Modify client/lib/services/cli/claude/claude_tool.dart
- Modify client/lib/services/cli/flashskyai/flashskyai_tool.dart
- Delete client/lib/services/cli/claude/capabilities/launch_args.dart
- Delete client/lib/services/cli/flashskyai/capabilities/launch_args.dart
- Test client/test/services/cli/claude_launch_capabilities_test.dart
- Test client/test/services/cli/flashskyai_launch_capabilities_test.dart
- Modify client/test/services/cli/cli_tool_adapter_test.dart to move shared launch assertions to registry launch tests, then delete it.

Interfaces:

- ClaudeTeamBehavior emits native identity only for native team mode: --team-name, --agent-name, --agent-id.
- FlashskyaiTeamBehavior emits native identity only for native team mode: --team, --member.
- Claude and FlashskyAI workspace providers emit their primary directory flag and repeated --add-dir.
- Permission providers map LaunchSecurityPolicy to supported flags and throw CliLaunchCapabilityException on unsupported combinations.

- [ ] Step 1: Add failing capability tests covering existing adapter expectations, native/mixed team identity, directories, model/provider/agent, prompt/settings, permission policy, and raw extra args.
- [ ] Step 2: Run both new test files and confirm failures because providers are absent.

    cd client && flutter test test/services/cli/claude_launch_capabilities_test.dart test/services/cli/flashskyai_launch_capabilities_test.dart

    Expected: FAIL.

- [ ] Step 3: Implement providers and make the two TeamBehavior implementations provide native identity contributions. Keep team/member extra args in UserExtraArgsCapability.
- [ ] Step 4: Register every provider in the two tool definitions, with one shared object instance per semantic capability.
- [ ] Step 5: Run focused capability tests and migrate/delete old adapter assertions.

    cd client && flutter test test/services/cli/claude_launch_capabilities_test.dart test/services/cli/flashskyai_launch_capabilities_test.dart test/services/cli/cli_tool_adapter_test.dart

    Expected: PASS after old adapter assertions are moved or the old test is deleted.

- [ ] Step 6: Commit the family CLI migration.

    git add client/lib/services/cli/claude client/lib/services/cli/flashskyai client/test/services/cli
    git commit -m "refactor(cli): compose Claude and FlashskyAI launch capabilities"

### Task 6: Migrate Codex and add first-class multi-directory launch support

Files:

- Create client/lib/services/cli/codex/capabilities/session_selection_launch.dart
- Create client/lib/services/cli/codex/capabilities/workspace_access_launch.dart
- Create client/lib/services/cli/codex/capabilities/model_launch.dart
- Create client/lib/services/cli/codex/capabilities/permission_launch.dart
- Modify client/lib/services/cli/codex/capabilities/team_behavior.dart
- Modify client/lib/services/cli/codex/codex_tool.dart
- Delete client/lib/services/cli/codex/capabilities/launch_args.dart
- Test client/test/services/cli/codex_launch_capabilities_test.dart
- Test client/test/integration/codex_config_materialize_launch_integration_test.dart

Interfaces:

- Codex session provider emits resume <id> in LaunchArgPhase.command.
- Codex workspace provider emits --cd <root> and one --add-dir <path> pair per non-empty additional directory.
- Codex permission provider emits both bypass flags only for the matching full-access/trust-bypass policy.

- [ ] Step 1: Write failing Codex tests for fresh launch, resume, fixed session, two additional directories, blank filtering, WSL conversion, model, and full-access policy.

    test('workspace capability emits every additional directory', () {
      final args = assembleCodex(
        workingDirectory: '/work',
        additionalDirectories: const ['/repo/a', '/repo/b', ''],
      );
      expect(args, containsAllInOrder([
        '--cd', '/work',
        '--add-dir', '/repo/a',
        '--add-dir', '/repo/b',
      ]));
    });

- [ ] Step 2: Run the focused test and confirm it fails before implementation.

    cd client && flutter test test/services/cli/codex_launch_capabilities_test.dart

    Expected: FAIL because Codex has no registered workspace provider.

- [ ] Step 3: Implement and register the Codex providers. Consume CliLaunchContext.additionalDirectories directly; add no new workspace/session field.
- [ ] Step 4: Run the unit and Codex config-materialization integration tests.

    cd client && flutter test test/services/cli/codex_launch_capabilities_test.dart test/integration/codex_config_materialize_launch_integration_test.dart

    Expected: PASS.

- [ ] Step 5: Commit the Codex migration.

    git add client/lib/services/cli/codex client/test/services/cli/codex_launch_capabilities_test.dart client/test/integration/codex_config_materialize_launch_integration_test.dart
    git commit -m "feat(codex): compose launch capabilities with multi-directory support"

### Task 7: Migrate Cursor and OpenCode representations

Files:

- Create client/lib/services/cli/cursor/capabilities/session_selection_launch.dart, workspace_access_launch.dart, model_launch.dart, and permission_launch.dart.
- Create client/lib/services/cli/opencode/capabilities/session_selection_launch.dart, model_launch.dart, agent_launch.dart, and user_extra_args_launch.dart.
- Modify client/lib/services/cli/cursor/cursor_tool.dart
- Modify client/lib/services/cli/opencode/opencode_tool.dart
- Delete client/lib/services/cli/cursor/capabilities/launch_args.dart
- Delete client/lib/services/cli/opencode/capabilities/launch_args.dart
- Test client/test/services/cli/cursor_launch_capabilities_test.dart
- Test client/test/services/cli/opencode_launch_capabilities_test.dart
- Test client/test/services/cli/config_profile/opencode_external_directories_test.dart

Interfaces:

- Cursor emits --workspace, repeated --add-dir, --model, and --force; mixed mode emits --approve-mcps through a team-behavior launch provider.
- OpenCode emits --session, --model provider/model, and --agent; external directories remain in the existing config-profile provider and are not emitted as unsupported argv.

- [ ] Step 1: Write failing Cursor/OpenCode tests, including OpenCode's explicit non-argv external-directory behavior.
- [ ] Step 2: Run focused tests and confirm missing-provider failures.

    cd client && flutter test test/services/cli/cursor_launch_capabilities_test.dart test/services/cli/opencode_launch_capabilities_test.dart

    Expected: FAIL.

- [ ] Step 3: Implement and register both provider sets. Keep Cursor HOME/trust materialization and OpenCode external-directory config in their existing provider capabilities.
- [ ] Step 4: Run focused and existing external-directory tests.

    cd client && flutter test test/services/cli/cursor_launch_capabilities_test.dart test/services/cli/opencode_launch_capabilities_test.dart test/services/cli/config_profile/opencode_external_directories_test.dart test/services/cli/cursor_cli_tool_adapter_test.dart test/services/cli/opencode_cli_tool_adapter_test.dart

    Expected: PASS after old adapter assertions are migrated.

- [ ] Step 5: Commit the Cursor/OpenCode migration.

    git add client/lib/services/cli/cursor client/lib/services/cli/opencode client/test/services/cli
    git commit -m "refactor(cli): compose Cursor and OpenCode launch capabilities"

### Task 8: Route every launch surface through the assembler

Files:

- Modify client/lib/services/session/launch_command_builder.dart
- Modify client/lib/services/session/shell_launch_spec.dart
- Modify client/lib/services/launch/session_connect_orchestrator.dart
- Modify client/lib/services/session/session_lifecycle_service.dart
- Modify client/lib/services/launch/session_shell_connector.dart
- Modify client/lib/cubits/team/team_launch_service.dart
- Modify client/lib/services/terminal/terminal_session.dart
- Modify client/lib/services/run/process_run_executor.dart and run_target_resolver.dart where argv is forwarded
- Test client/test/services/session/launch_command_builder_test.dart
- Test client/test/services/session/session_lifecycle_simple_test.dart
- Test client/test/services/launch/session_shell_connector_test.dart
- Test client/test/cubits/team/team_launch_service_test.dart

Interfaces:

- LaunchCommandBuilder.buildArgumentsFromContext delegates to CliLaunchArgAssembler using the resolved CliToolDefinition.
- buildShellArguments applies environment-derived settings/prompt values to CliLaunchContext, then calls the same assembler.
- preview, launch, PTY, and SSH paths consume the same assembled token list.

- [ ] Step 1: Add boundary tests comparing preview, shell, and direct context assembly for the same semantic context.
- [ ] Step 2: Run focused launch tests and record each remaining old buildArguments call.

    cd client && flutter test test/services/session/launch_command_builder_test.dart test/services/session/session_lifecycle_simple_test.dart

    Expected: FAIL after old route removal, identifying remaining callers.

- [ ] Step 3: Replace LaunchCommandBuilder's CliSessionCapability lookup with CliLaunchArgAssembler and CliToolDefinition. Remove buildSessionPrefixArgs from LaunchCommandBuilder.
- [ ] Step 4: Update ShellLaunchSpec and lifecycle/orchestration call sites so the terminal boundary receives CliLaunchContext plus lifecycle LaunchPlan, not an adapter.
- [ ] Step 5: Run launch builder, lifecycle, shell connector, and team launch tests.

    cd client && flutter test test/services/session/launch_command_builder_test.dart test/services/session/session_lifecycle_simple_test.dart test/services/launch/session_shell_connector_test.dart test/cubits/team/team_launch_service_test.dart

    Expected: PASS with identical argv across preview, PTY, external-terminal, and SSH paths.

- [ ] Step 6: Delete client/lib/services/cli/cli_tool_adapter.dart, client/lib/services/cli/claude/capabilities/launch_args.dart, client/lib/services/cli/flashskyai/capabilities/launch_args.dart, client/lib/services/cli/codex/capabilities/launch_args.dart, client/lib/services/cli/cursor/capabilities/launch_args.dart, and client/lib/services/cli/opencode/capabilities/launch_args.dart.
- [ ] Step 7: Require zero legacy launch-builder matches.

    rg -n "CliToolAdapter|buildArguments\\(|buildSessionPrefixArgs|CliSessionCapability.*build" client/lib client/test --glob '*.dart'

    Expected: no legacy launch-builder references.

- [ ] Step 8: Commit the launch-surface migration.

    git add client/lib/services/session client/lib/services/launch client/lib/cubits/team/team_launch_service.dart client/lib/services/terminal client/lib/services/run client/test/services/session client/test/services/launch client/test/cubits/team
    git commit -m "refactor(cli): route all launch surfaces through capability assembler"

### Task 9: Update permission UI, launch forms, and persisted consumers

Files:

- Modify client/lib/pages/automations/automation_editor_dialog.dart
- Modify client/lib/pages/automations/automation_editor_form_body.dart
- Modify client/lib/pages/automations/automation_editor_launch_section.dart
- Modify client/lib/pages/chat/session_chat_compose_section.dart
- Modify client/lib/pages/home_workspace/workspace/unbound_compose_body.dart
- Modify client/lib/pages/home_workspace/workspace/workspace_landing_team_settings_dialog.dart
- Modify client/lib/pages/home_workspace/workspace/workspace_session_actions.dart
- Modify client/lib/pages/team_config/team_config_member_section.dart
- Modify client/lib/services/home_workspace/landing_prefs_store.dart
- Modify client/lib/utils/workspace/landing_draft_resolver.dart
- Modify client/lib/widgets/compose/compose_chrome.dart
- Modify client/lib/widgets/compose/compose_permission_chip.dart
- Modify client/lib/widgets/compose/workspace_compose_card.dart
- Modify client/lib/l10n/app_en.arb and client/lib/l10n/app_zh.arb
- Test client/test/widgets/compose/compose_chips_test.dart
- Test client/test/widgets/compose/compose_chrome_test.dart
- Test client/test/widgets/compose/workspace_compose_card_test.dart
- Test client/test/pages/chat/session_chat_submit_gate_test.dart
- Test client/test/utils/workspace/landing_draft_resolver_test.dart

Interfaces:

- Permission UI edits LaunchSecurityPolicy, not a boolean.
- UI exposes approval, sandbox, and hook-trust dimensions; plan-only interaction is shown only where the selected CLI declares support.
- Launch forms display a capability error when a selected CLI cannot represent a requested policy.

- [ ] Step 1: Add failing widget/model tests for automatic approval, plan-only interaction, manual approval, and full-access policy.
- [ ] Step 2: Run focused UI tests and verify old boolean expectations fail.

    cd client && flutter test test/widgets/compose/compose_chips_test.dart test/widgets/compose/compose_chrome_test.dart test/widgets/compose/workspace_compose_card_test.dart test/pages/chat/session_chat_submit_gate_test.dart

    Expected: FAIL because widgets still bind to dangerouslySkipPermissions.

- [ ] Step 3: Replace boolean controls with policy controls and add localized labels to both ARB files. Keep dangerous wording explicit.
- [ ] Step 4: Update landing drafts, automation editors, workspace compose, and chat submit gates to persist and pass policy objects.
- [ ] Step 5: Run focused UI and resolver tests.

    cd client && flutter test test/widgets/compose/compose_chips_test.dart test/widgets/compose/compose_chrome_test.dart test/widgets/compose/workspace_compose_card_test.dart test/pages/chat/session_chat_submit_gate_test.dart test/utils/workspace/landing_draft_resolver_test.dart

    Expected: PASS with no production-code references to dangerouslySkipPermissions.

- [ ] Step 6: Commit the policy UI migration.

    git add client/lib/pages/automations client/lib/pages/chat client/lib/pages/home_workspace client/lib/pages/team_config client/lib/services/home_workspace client/lib/utils/workspace client/lib/widgets/compose client/lib/l10n client/test/widgets/compose client/test/pages/chat client/test/utils/workspace
    git commit -m "refactor(ui): expose structured launch security policies"

### Task 10: Update documentation and run full verification

Files:

- Modify docs/cli-architecture.md
- Modify docs/DEVELOPMENT.md only if launch-test commands need clarification
- Delete migrated legacy adapter tests after their assertions exist in capability tests
- Test all client/test/services/cli/*launch_capabilities_test.dart and registry launch tests

- [ ] Step 1: Document the capability-provider/assembler flow, contribution phases, permission policy mapping, and OpenCode non-argv directory behavior in docs/cli-architecture.md.
- [ ] Step 2: Add a built-in CLI contract test iterating over all five launchable definitions and verifying each documented launch provider is registered.
- [ ] Step 3: Run focused launch and permission suites.

    cd client && flutter test test/services/cli/registry/launch test/services/cli/*launch_capabilities_test.dart test/services/session/launch_command_builder_test.dart test/services/session/session_continue_overrides_apply_test.dart

    Expected: PASS with zero legacy adapter references.

- [ ] Step 4: Run repository verification required by AGENTS.md.

    cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration

    Expected: both commands exit 0. Any pre-existing failure must be identified separately; do not claim completion if a failure is caused by this refactor.

- [ ] Step 5: Run relevant integration tests when prerequisites are available.

    cd client && flutter test test/integration/codex_config_materialize_launch_integration_test.dart test/integration/cli_message_matrix_codex_test.dart

    Expected: PASS or an explicit prerequisite skip from the test harness.

- [ ] Step 6: Review the final diff and verify the requirements checklist.

    rg -n "CliToolAdapter|dangerouslySkipPermissions|buildSessionPrefixArgs" client/lib client/test --glob '*.dart'
    git diff --check
    git status --short

    Expected: no legacy production references, clean diff formatting, and only intended task files changed.

- [ ] Step 7: Commit documentation and final test updates.

    git add docs/cli-architecture.md docs/DEVELOPMENT.md client/test
    git commit -m "docs(cli): document capability-based launch assembly"
