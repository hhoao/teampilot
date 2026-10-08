# CLI Full-Access-Only Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every built-in CLI expose only `fullAccess`, remove user-configurable launch permission state, and enforce the restriction at the shared CLI launch boundary.

**Architecture:** Add a typed `CliLaunchSecurityCapability` to every built-in CLI definition. The capability declares whether user configuration is available and which policies are supported; existing per-CLI `permissionLaunch` providers continue translating the supported `fullAccess` policy into CLI-specific argv or configuration. Remove permission policy from persisted and session override models, make compose/configuration UI capability-driven, and reject unsupported policies in both interactive and headless assemblers.

**Tech Stack:** Dart, Flutter, `CliToolRegistry`, typed CLI capabilities, JSON model serialization, Flutter widget tests, repository test runner.

## Global Constraints

- Never invoke `flutter test` directly; use `cd client && dart run tool/run_tests.dart` with concrete test paths or options.
- Before claiming completion run `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Preserve all pre-existing user changes in the dirty worktree, especially `client/lib/services/cli/codex/capabilities/permission_launch.dart`, `docs/cli-architecture.md`, and the listed team-generation/workbench files.
- Keep CLI behavior in definitions and capabilities; do not add page-level `if (cli == ...)` permission branches.
- Use `sessionRosterMembers(session, team)` for member placement wherever touched.
- Use l10n from `client/lib/l10n/app_en.arb` and `app_zh.arb`; do not edit generated localization Dart files directly.
- Use `AppLogger` for diagnostics and l10n/cubit state for user-visible failures; do not add `print`.
- Use constructor injection for filesystem/subprocess boundaries in tests.
- Keep `LaunchSecurityPolicy` as launch-layer semantic input for future capability expansion, but remove its persistence/override role from current product state.

---

### Task 1: Add and register the launch-security capability

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/cli_launch_security_capability.dart`
- Modify: `client/lib/services/cli/registry/cli_tool_registry.dart`
- Modify: `client/lib/services/cli/claude/claude_tool.dart`
- Modify: `client/lib/services/cli/codex/codex_tool.dart`
- Modify: `client/lib/services/cli/cursor/cursor_tool.dart`
- Modify: `client/lib/services/cli/flashskyai/flashskyai_tool.dart`
- Modify: `client/lib/services/cli/opencode/opencode_tool.dart`
- Create: `client/test/services/cli/registry/cli_launch_security_capability_test.dart`
- Modify: `client/test/services/cli/registry/cli_tool_registry_test.dart`

**Interfaces:**
- Produces `CliLaunchSecurityCapability` with `supportsUserConfiguration` and `supportedPolicies`.
- Produces `FullAccessOnlyCliLaunchSecurityCapability`, whose values are `false` and `{LaunchSecurityPolicy.fullAccess}`.
- Produces `CliToolRegistry.launchSecurityFor(CliTool id)`, which returns the registered capability or throws a `StateError` naming the missing CLI.

- [ ] **Step 1: Write the failing capability contract test.** Add a test that obtains `CliToolRegistry.builtIn()`, iterates over `CliTool.values`, and asserts each CLI returns a non-null capability, `supportsUserConfiguration == false`, and `supportedPolicies == {LaunchSecurityPolicy.fullAccess}`. Add a test that a registry definition without the capability causes `launchSecurityFor` to throw a `StateError` containing the CLI value.

```dart
test('all built-in CLIs expose a full-access-only security capability', () {
  final registry = CliToolRegistry.builtIn();

  for (final cli in CliTool.values) {
    final capability = registry.launchSecurityFor(cli);
    expect(capability.supportsUserConfiguration, isFalse);
    expect(
      capability.supportedPolicies,
      {LaunchSecurityPolicy.fullAccess},
    );
  }
});
```

- [ ] **Step 2: Run the focused test and verify it fails.**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/cli_launch_security_capability_test.dart`

Expected: FAIL because `CliLaunchSecurityCapability` and `launchSecurityFor` do not exist.

- [ ] **Step 3: Implement the capability and registry helper.** Import `LaunchSecurityPolicy` and `CliCapability`, then add:

```dart
abstract interface class CliLaunchSecurityCapability implements CliCapability {
  bool get supportsUserConfiguration;
  Set<LaunchSecurityPolicy> get supportedPolicies;
}

final class FullAccessOnlyCliLaunchSecurityCapability
    implements CliLaunchSecurityCapability {
  const FullAccessOnlyCliLaunchSecurityCapability();

  @override
  bool get supportsUserConfiguration => false;

  @override
  Set<LaunchSecurityPolicy> get supportedPolicies =>
      const {LaunchSecurityPolicy.fullAccess};
}
```

Add this registry helper:

```dart
CliLaunchSecurityCapability launchSecurityFor(CliTool id) {
  final capability = capability<CliLaunchSecurityCapability>(id);
  if (capability == null) {
    throw StateError(
      'CLI ${id.value} must register CliLaunchSecurityCapability',
    );
  }
  return capability;
}
```

Add a `launchSecurity` constructor field and definition capability entry to all five tool classes. Use `const FullAccessOnlyCliLaunchSecurityCapability()` as each default, and place it immediately before the existing `permissionLaunch` entry so security capability ordering is stable.

- [ ] **Step 4: Run the focused tests and verify they pass.**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/cli_launch_security_capability_test.dart test/services/cli/registry/cli_tool_registry_test.dart`

Expected: PASS, including the existing registry tests.

- [ ] **Step 5: Commit the capability contract.**

```bash
git add client/lib/services/cli/registry/capabilities/cli_launch_security_capability.dart client/lib/services/cli/registry/cli_tool_registry.dart client/lib/services/cli/claude/claude_tool.dart client/lib/services/cli/codex/codex_tool.dart client/lib/services/cli/cursor/cursor_tool.dart client/lib/services/cli/flashskyai/flashskyai_tool.dart client/lib/services/cli/opencode/opencode_tool.dart client/test/services/cli/registry/cli_launch_security_capability_test.dart client/test/services/cli/registry/cli_tool_registry_test.dart
git commit -m "feat(cli): register launch security capabilities"
```

### Task 2: Enforce full access at interactive and headless launch boundaries

**Files:**
- Modify: `client/lib/services/cli/registry/launch/cli_launch_arg_assembler.dart`
- Modify: `client/lib/services/cli/claude/capabilities/permission_launch.dart`
- Modify: `client/lib/services/cli/codex/capabilities/permission_launch.dart`
- Modify: `client/lib/services/cli/cursor/capabilities/permission_launch.dart`
- Modify: `client/lib/services/cli/flashskyai/capabilities/permission_launch.dart`
- Modify: `client/lib/services/cli/opencode/capabilities/permission_launch.dart`
- Modify: `client/lib/services/cli/registry/launch/cli_launch_capability_error.dart`
- Modify: `client/test/services/cli/registry/launch/cli_launch_arg_assembler_test.dart`
- Modify: `client/test/services/cli/registry/launch/built_in_cli_launch_provider_contract_test.dart`
- Modify: `client/test/services/cli/claude_launch_capabilities_test.dart`
- Modify: `client/test/services/cli/codex_launch_capabilities_test.dart`
- Modify: `client/test/services/cli/cursor_launch_capabilities_test.dart`
- Modify: `client/test/services/cli/flashskyai_launch_capabilities_test.dart`
- Modify: `client/test/services/cli/opencode_launch_capabilities_test.dart`

**Interfaces:**
- `CliLaunchArgAssembler.assemble` and `.assembleHeadless` validate the relevant security policy against the tool definition before collecting contributions.
- The validation error uses contribution key `launch-security-policy`, the concrete CLI id, and a reason listing the requested policy and supported policies.
- Each existing permission provider emits its current full-access contribution and throws for every other policy when called directly.

- [ ] **Step 1: Write failing assembler tests.** Add an interactive test and a headless test using a built-in CLI definition and a non-full-access policy. Assert `CliLaunchCapabilityException`, `cli`, `contributionKey == 'launch-security-policy'`, and a reason containing `fullAccess`. Add a parameterized-style loop over all five definitions for the interactive path.

```dart
test('rejects a policy not declared by the CLI security capability', () {
  final tool = CliToolRegistry.builtIn().tryGet(CliTool.codex)!;
  final context = CliLaunchContext(
    team: TeamProfile(id: 'team', name: 'Team'),
    member: TeamMemberConfig(id: 'member', name: 'Member'),
    launchSecurityPolicy: LaunchSecurityPolicy.askReadOnlyTrusted,
  );

  expect(
    () => const CliLaunchArgAssembler().assemble(tool, context),
    throwsA(
      isA<CliLaunchCapabilityException>()
          .having((e) => e.cli, 'cli', CliTool.codex)
          .having(
            (e) => e.contributionKey,
            'contributionKey',
            'launch-security-policy',
          )
          .having((e) => e.reason, 'reason', contains('fullAccess')),
    ),
  );
});
```

- [ ] **Step 2: Run the launch assembler tests and verify the new tests fail.**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/launch/cli_launch_arg_assembler_test.dart`

Expected: FAIL because the assembler currently allows providers to interpret unsupported policies.

- [ ] **Step 3: Add one shared validation path to the assembler.** Add a private method that finds the single `CliLaunchSecurityCapability` from the definition, throws a registration error if missing, and throws `CliLaunchCapabilityException` if the requested policy is absent from `supportedPolicies`. Call it in `assemble` with `context.launchSecurityPolicy` and in `assembleHeadless` with `context.securityPolicy`, before `_assemble`.

Update `cli_launch_arg_assembler_test.dart`’s `FakeCliTool` fixture so every existing ordering/contribution test registers `const FullAccessOnlyCliLaunchSecurityCapability()` by default. Add a constructor flag used only by the missing-capability test to verify the assembler’s fail-closed registration error.

The exception construction must be equivalent to:

```dart
throw CliLaunchCapabilityException(
  cli: tool.id,
  contributionKey: 'launch-security-policy',
  reason:
      'CLI ${tool.id.value} supports launch security policies '
      '${capability.supportedPolicies.map((p) => p.toString()).join(', ')}, '
      'but received $policy.',
);
```

Do not add a fallback policy or mutate either launch context.

- [ ] **Step 4: Restrict the five direct permission providers.** Keep the existing full-access arguments exactly as they are. Remove `cliDefault`, ask/read-only, auto-approve, and partial Codex branches from the normal provider paths. Each provider must throw `CliLaunchCapabilityException` for a non-full policy, using its existing CLI-specific key only when the provider is called directly. Keep OpenCode validation for both interactive and headless contexts, but accept only `LaunchSecurityPolicy.fullAccess`.

- [ ] **Step 5: Update launch capability tests.** Replace tests that expect CLI-default, ask/read-only, or auto-approve argv with tests that expect the shared assembler rejection. Keep full-access argv assertions unchanged for Claude, FlashskyAI, Codex, Cursor, and OpenCode’s full-access configuration behavior. Include direct provider rejection tests for OpenCode’s headless constraint.

- [ ] **Step 6: Run all focused launch tests.**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/launch test/services/cli/claude_launch_capabilities_test.dart test/services/cli/codex_launch_capabilities_test.dart test/services/cli/cursor_launch_capabilities_test.dart test/services/cli/flashskyai_launch_capabilities_test.dart test/services/cli/opencode_launch_capabilities_test.dart`

Expected: PASS with full-access output unchanged and all non-full requests rejected.

- [ ] **Step 7: Commit the launch boundary.**

```bash
git add client/lib/services/cli/registry/launch/cli_launch_arg_assembler.dart client/lib/services/cli/registry/launch/cli_launch_capability_error.dart client/lib/services/cli/claude/capabilities/permission_launch.dart client/lib/services/cli/codex/capabilities/permission_launch.dart client/lib/services/cli/cursor/capabilities/permission_launch.dart client/lib/services/cli/flashskyai/capabilities/permission_launch.dart client/lib/services/cli/opencode/capabilities/permission_launch.dart client/test/services/cli/registry/launch client/test/services/cli/claude_launch_capabilities_test.dart client/test/services/cli/codex_launch_capabilities_test.dart client/test/services/cli/cursor_launch_capabilities_test.dart client/test/services/cli/flashskyai_launch_capabilities_test.dart client/test/services/cli/opencode_launch_capabilities_test.dart
git commit -m "feat(cli): enforce full-access-only launch policies"
```

### Task 3: Remove persisted and session-level permission state

**Files:**
- Modify: `client/lib/models/launch_security_policy.dart`
- Modify: `client/lib/models/team_config.dart`
- Modify: `client/lib/models/team_roster_slot.dart`
- Modify: `client/lib/models/workspace_agent_config.dart`
- Modify: `client/lib/models/automation.dart`
- Modify: `client/lib/models/landing_launch_context.dart`
- Modify: `client/lib/models/session_continue_overrides.dart`
- Modify: `client/lib/services/home_workspace/landing_prefs_store.dart`
- Modify: `client/lib/services/automation/automation_dispatcher.dart`
- Modify: `client/lib/services/session/session_continue_overrides_apply.dart`
- Modify: `client/lib/services/session/launch_command_builder.dart`
- Modify: `client/lib/services/session/shell_launch_spec.dart`
- Modify: `client/lib/services/session/session_lifecycle_service.dart`
- Modify: `client/lib/services/launch/session_runtime_plan_builder.dart`
- Modify: `client/lib/services/launch/session_shell_connector.dart`
- Modify: `client/lib/services/session/remote_ssh_launch_constraints.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`
- Modify: `client/lib/services/team_bus/teammate_roster_profile.dart`
- Modify: `client/lib/services/team_bus/mcp/toolkit/teammate_bus_tool_format.dart`
- Modify: `client/lib/services/team_generation/models/team_generation_launch.dart`
- Modify: `client/lib/services/team_generation/models/team_generation_job.dart`
- Modify: `client/lib/services/cli/codex/capabilities/provider.dart`
- Modify: `client/lib/cubits/chat/session_continue_overrides_controller.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Modify: `client/lib/cubits/launch_profile_cubit.dart`
- Modify: `client/lib/cubits/team/launch_profile_selectors.dart`
- Modify: `client/lib/cubits/team/team_roster_editor.dart`
- Modify: `client/lib/utils/workspace/landing_draft_resolver.dart`
- Modify: `client/lib/services/team_generation/team_generation_coordinator.dart`
- Modify: model, service, cubit, repository, and utility tests listed by the `rg` audit below

**Interfaces:**
- Persisted models no longer expose `launchSecurityPolicy` or `LaunchSecurityPolicyOverride` fields.
- `SessionContinueOverridesController` no longer exposes `patchSecurityPolicy` or `persistSecurityPolicy`.
- Launch contexts still carry internal security input, defaulting to `LaunchSecurityPolicy.fullAccess`; callers construct that value explicitly rather than reading it from team/member/session state.

- [ ] **Step 1: Capture the exact removal surface before editing.** Run:

```bash
rg -l "launchSecurityPolicy|LaunchSecurityPolicyOverride|securityPolicyValue" client/lib client/test --glob '*.dart' | sort
```

Review the output against the files in this task. Do not reset or discard unrelated changes. Any additional reference must be classified as persisted state, UI state, launch plumbing, or a test fixture before changing it.

- [ ] **Step 2: Write model serialization tests for the new contract.** In the existing model tests, construct the affected models and assert their `toJson()` maps do not contain `launchSecurityPolicy`. Remove round-trip expectations for the deleted field. In `workspace_launch_prefs_store_test.dart`, assert saved landing preferences omit the key. In `session_continue_overrides_test.dart`, assert both top-level and member override JSON omit the key.

```dart
test('automation JSON does not persist launch security policy', () {
  final json = sampleAutomation(
    id: 'launch',
    workspaceId: 'ws1',
  ).toJson();

  expect(json.containsKey('launchSecurityPolicy'), isFalse);
});
```

- [ ] **Step 3: Run the affected model tests and verify they fail.**

Run: `cd client && dart run tool/run_tests.dart test/models test/services/home_workspace/workspace_launch_prefs_store_test.dart test/models/session_continue_overrides_test.dart`

Expected: FAIL because the current models still serialize and expose permission state.

- [ ] **Step 4: Remove policy persistence from model constructors and JSON.** Delete the policy imports, constructor parameters, fields, `copyWith` parameters, equality terms, hash-code terms, `fromJson` reads, and `toJson` writes from `TeamProfile`/`TeamMemberConfig`, `TeamRosterSlotOverrides`, `WorkspaceAgentConfig`, `Automation`, `LandingLaunchContext`, `LandingPrefs`, `SessionMemberContinueOverride`, and `SessionContinueOverrides`. Delete `LaunchSecurityPolicyOverride` and its nullable enum helpers from `launch_security_policy.dart`; retain only launch-layer policy semantics needed by providers and contexts.

- [ ] **Step 5: Remove policy merge and persistence operations.** Delete security branches from `session_continue_overrides_apply.dart` and remove `patchSecurityPolicy`/`persistSecurityPolicy` plus their callers from `SessionContinueOverridesController`, `ChatCubit`, `LaunchProfileCubit`, and session continuation flows. Keep preset/provider/model/effort continuation behavior intact.

- [ ] **Step 6: Reconnect launch contexts to fixed full access.** In `launch_command_builder.dart`, `shell_launch_spec.dart`, `session_lifecycle_service.dart`, `session_runtime_plan_builder.dart`, and `landing_draft_resolver.dart`, replace reads from member/team/landing/automation policy state with `LaunchSecurityPolicy.fullAccess` when constructing `CliLaunchContext` or `CliHeadlessLaunchContext`. Keep the internal policy on `CliLaunchContext`, `CliHeadlessLaunchContext`, remote SSH constraints, and security materializers so the shared assembler and provider contracts remain explicit.

- [ ] **Step 7: Remove generated/session state references from other launch surfaces.** In `automation_dispatcher.dart` and `workspace_session_actions.dart`, stop creating security overrides for newly created sessions. In `teammate_roster_profile.dart` and `teammate_bus_tool_format.dart`, remove the roster policy field from the TeamBus profile and MCP representation. In `codex/capabilities/provider.dart`, pass `LaunchSecurityPolicy.fullAccess` to the managed-hook overlay instead of reading a member policy. Keep `session_shell_connector.dart` and `remote_ssh_launch_constraints.dart` reading the internal launch-context policy, which is now always full access.

- [ ] **Step 8: Remove generated/session state references from team generation.** Delete `launchSecurityPolicyValue` from `TeamGenerationLaunch`, remove its JSON read/write and job defaults, and stop setting it in `team_generation_coordinator.dart`. The team-generation protocol must no longer accept a user-selected policy value.

- [ ] **Step 9: Run the model and session tests.**

Run: `cd client && dart run tool/run_tests.dart test/models test/services/session test/services/launch test/services/home_workspace test/cubits/chat/session_continue_overrides_controller_test.dart test/cubits/chat_cubit_continue_overrides_test.dart`

Expected: PASS with no permission policy persisted or merged.

- [ ] **Step 10: Commit the state removal.**

```bash
git add client/lib/models client/lib/services/home_workspace/landing_prefs_store.dart client/lib/services/session client/lib/services/launch/session_runtime_plan_builder.dart client/lib/cubits/chat/session_continue_overrides_controller.dart client/lib/cubits/chat_cubit.dart client/lib/cubits/launch_profile_cubit.dart client/lib/cubits/team/launch_profile_selectors.dart client/lib/cubits/team/team_roster_editor.dart client/lib/utils/workspace/landing_draft_resolver.dart client/lib/services/team_generation/team_generation_coordinator.dart client/test/models client/test/services/session client/test/services/launch client/test/services/home_workspace client/test/cubits/chat/session_continue_overrides_controller_test.dart client/test/cubits/chat_cubit_continue_overrides_test.dart
git commit -m "refactor: remove persisted CLI permission policies"
```

### Task 4: Make compose and configuration UI capability-driven

**Files:**
- Modify: `client/lib/widgets/compose/compose_chrome.dart`
- Modify: `client/lib/widgets/compose/workspace_compose_card.dart`
- Retain and test: `client/lib/widgets/compose/compose_permission_chip.dart`
- Modify: `client/lib/pages/chat/session_chat_compose_section.dart`
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart`
- Modify: `client/lib/pages/team_config/team_config_member_section.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_landing_team_settings_dialog.dart`
- Modify: `client/lib/pages/automations/automation_editor_dialog.dart`
- Modify: `client/lib/pages/automations/automation_editor_form_body.dart`
- Modify: `client/lib/pages/automations/automation_editor_launch_section.dart`
- Modify: compose, chat, team-config, landing, and automation widget tests
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`

**Interfaces:**
- Add `ComposePermissionControl` containing the policy, labels, and selection callback currently spread across `ComposeChrome` fields.
- `UnboundComposeChrome.permissionControl` and `BoundComposeChrome.permissionControl` are nullable.
- `WorkspaceComposeCard` renders `ComposePermissionChip` only when `permissionControl != null`.
- Current pages do not create the control because `registry.launchSecurityFor(cli).supportsUserConfiguration` is false for every built-in CLI.

- [ ] **Step 1: Write the failing compose tests.** Add tests to `workspace_compose_card_test.dart` that build each compose mode with no `permissionControl` and assert `find.byType(ComposePermissionChip)` finds zero widgets. Add a retained-component test to `compose_chips_test.dart` that gives `ComposePermissionChip` a configurable policy set and verifies it still emits the selected policy.

- [ ] **Step 2: Run the compose tests and verify the new tests fail.**

Run: `cd client && dart run tool/run_tests.dart test/widgets/compose/workspace_compose_card_test.dart test/widgets/compose/compose_chips_test.dart`

Expected: FAIL because the current chrome constructors and card unconditionally pass/render permission fields.

- [ ] **Step 3: Refactor `ComposeChrome` to one optional control.** Add this model to `compose_chrome.dart`:

```dart
final class ComposePermissionControl {
  const ComposePermissionControl({
    required this.launchSecurityPolicy,
    required this.defaultLabel,
    required this.fullAccessLabel,
    required this.onSelected,
    this.askReadOnlyLabel,
    this.autoApproveWorkspaceWriteLabel,
    this.customLabel,
  });

  final LaunchSecurityPolicy launchSecurityPolicy;
  final String defaultLabel;
  final String fullAccessLabel;
  final String? askReadOnlyLabel;
  final String? autoApproveWorkspaceWriteLabel;
  final String? customLabel;
  final ValueChanged<LaunchSecurityPolicy> onSelected;
}
```

Replace the existing permission fields on both chrome classes with `final ComposePermissionControl? permissionControl;` and update all constructors and call sites.

- [ ] **Step 4: Update `WorkspaceComposeCard`.** Change `_unboundLeadingChips` and `_boundLeadingChips` to add `ComposePermissionChip` only for a non-null control, forwarding its fields. Update `_hasBoundToolbar` to check `permissionControl != null`. Keep the existing chip implementation independent from the registry.

- [ ] **Step 5: Stop constructing permission controls in current pages.** In `session_chat_compose_section.dart` and `unbound_compose_body.dart`, remove permission labels, callbacks, `_onPermissionSelected`, landing preference writes, and policy state. Use `CliToolRegistryScope` only for capability queries needed by other controls; do not add CLI-specific conditionals. Remove the team member skip-permissions switch and landing team-settings permission toggle because current CLI capabilities are not user-configurable. Remove the automation permission field and its dialog/form callbacks.

- [ ] **Step 6: Remove obsolete localization entries.** After a repository-wide `rg` confirms each key has no remaining production use, remove only the permission-selection strings from `app_en.arb` and `app_zh.arb`. Keep permission-request/permission-answer strings used by runtime attention cards. Regenerate localization using the project’s existing generation command; never hand-edit generated files.

- [ ] **Step 7: Run UI tests and verify they pass.**

Run: `cd client && dart run tool/run_tests.dart test/widgets/compose test/pages/chat/session_history_continue_chrome_test.dart test/pages/automations/automation_editor_dialog_test.dart test/pages/team_config test/pages/home_workspace/workspace`

Expected: PASS, with no permission selector in current compose/configuration surfaces and no unrelated compose controls removed.

- [ ] **Step 8: Commit the UI contraction.**

```bash
git add client/lib/widgets/compose client/lib/pages/chat/session_chat_compose_section.dart client/lib/pages/home_workspace/workspace/unbound_compose_body.dart client/lib/pages/team_config/team_config_member_section.dart client/lib/pages/home_workspace/workspace/workspace_landing_team_settings_dialog.dart client/lib/pages/automations client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/widgets/compose client/test/pages/chat/session_history_continue_chrome_test.dart client/test/pages/automations/automation_editor_dialog_test.dart client/test/pages/team_config client/test/pages/home_workspace/workspace
git commit -m "feat(ui): hide unsupported CLI permission controls"
```

### Task 5: Update architecture documentation and complete reference cleanup

**Files:**
- Modify: `docs/cli-architecture.md`
- Do not modify: unrelated pre-existing changes in the same files unless the permission-only hunk requires it

**Interfaces:**
- Documentation states that all current built-in CLIs register a non-configurable full-access security capability.
- The launch-policy table distinguishes the fixed current product policy from future CLI capability expansion.

- [ ] **Step 1: Audit remaining production references.** Run:

```bash
rg -n "launchSecurityPolicy|LaunchSecurityPolicyOverride|askReadOnlyTrusted|autoApproveWorkspaceWriteTrusted|LaunchSecurityPolicy\.cliDefault|memberDangerouslySkipPermissions|automationsPermissions" client/lib client/test docs/cli-architecture.md --glob '*.dart' --glob '*.md' --glob '*.arb'
```

Classify each remaining result as intentional launch-layer semantic code, runtime permission handling, test-only unsupported-policy coverage, or stale product configuration. Remove only stale product configuration references.

- [ ] **Step 2: Update `docs/cli-architecture.md` in targeted hunks.** Preserve the file’s pre-existing uncommitted edits. Document `CliLaunchSecurityCapability`, the `{fullAccess}` registration for all five current CLIs, assembler rejection of unsupported policies, and the absence of persisted/user-configurable launch policy. Keep the existing per-CLI full-access argv/configuration mapping accurate.

- [ ] **Step 3: Run documentation and formatting checks.**

Run: `git diff --check -- docs/cli-architecture.md client/lib client/test`

Expected: no whitespace errors, no stale permission-selection references outside intentional launch/runtime tests.

- [ ] **Step 4: Commit the documentation and cleanup.**

```bash
git add docs/cli-architecture.md client/lib client/test
git commit -m "docs(cli): document fixed full-access security policy"
```

### Task 6: Full verification and final review

**Files:**
- No new production files; inspect all files changed by Tasks 1–5.

- [ ] **Step 1: Inspect the final diff and worktree.** Run:

```bash
git status --short
git diff HEAD~5..HEAD --stat
git diff --check
```

Confirm no unrelated pre-existing change was staged or committed by the implementation work.

- [ ] **Step 2: Run the focused CLI and UI test set through the repository runner.**

Run:

```bash
cd client && dart run tool/run_tests.dart test/services/cli/registry test/services/cli test/models test/services/session test/services/launch test/services/home_workspace test/widgets/compose test/pages/automations
```

Expected: PASS.

- [ ] **Step 3: Run static analysis.**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: exit code 0 with no new errors or warnings caused by this change.

- [ ] **Step 4: Run the complete suite once.**

Run: `cd client && dart run tool/run_tests.dart`

Expected: PASS. Do not invoke `flutter test` directly.

- [ ] **Step 5: Perform a final behavior audit.** Confirm all five built-in definitions expose the capability, all launch contexts use full access, non-full policies fail at the assembler, no current UI shows `ComposePermissionChip`, and no persisted model writes a permission policy field.

- [ ] **Step 6: Request code review before claiming completion.** Use the repository code-review workflow against the final diff, then report the verification commands and results without claiming success for any command that was not run.
