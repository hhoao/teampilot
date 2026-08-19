# CLI Launch Argument Capabilities Design

**Date:** 2026-08-18

**Status:** Proposed

## Goal

Replace monolithic per-CLI `buildArguments()` adapters with composable launch-argument capabilities. Each CLI capability may contribute the arguments owned by its semantic area, while one assembler owns ordering, conflict validation, and final argv construction.

The redesign explicitly does not preserve the old monolithic adapter API or its compatibility wrappers.

## Current problem

`CliLaunchContext` already carries the semantic launch inputs, but each CLI currently renders the complete argv in one file:

- `claude/capabilities/launch_args.dart`
- `flashskyai/capabilities/launch_args.dart`
- `codex/capabilities/launch_args.dart`
- `cursor/capabilities/launch_args.dart`
- `opencode/capabilities/launch_args.dart`

This causes three problems:

1. A capability can own runtime behavior but cannot own the corresponding launch flags. For example, `ClaudeTeamBehavior` knows whether native teams are supported, while team flags are assembled elsewhere.
2. Shared semantic inputs are duplicated across adapters. Session selection, working directories, model, permissions, and extra arguments each have several independent implementations.
3. Ordering and conflicts are implicit in list mutation. Codex's missing `--add-dir` is an example of a capability being omitted from one adapter.

The current `CliSessionCapability` also combines lifecycle, configuration-directory layout, connect gating, and argv generation. These concerns need separate interfaces.

## Design principles

- Capabilities own semantic behavior and the CLI encoding of that behavior.
- A capability contributes immutable argument fragments; it never mutates a shared argv list.
- The assembler is the only component that orders, validates, and flattens fragments.
- Shared semantics may have different encodings. `additional directories` is one semantic capability, but OpenCode uses configuration while Codex uses `--add-dir`.
- Unsupported requested behavior is an explicit launch error or warning according to the capability contract; it is never silently dropped.
- Argument capability composition is per CLI. There is no universal assumption that every CLI supports every semantic input.
- Raw user extra arguments are an escape hatch and are always emitted last.

## Target architecture

```text
CliLaunchContext (semantic request)
        |
        v
CliToolDefinition.capabilities
        |
        +-- TeamBehaviorCapability + CliLaunchArgProvider
        +-- WorkspaceAccessCapability + CliLaunchArgProvider
        +-- SessionSelectionCapability + CliLaunchArgProvider
        +-- ModelLaunchCapability + CliLaunchArgProvider
        +-- PermissionLaunchCapability + CliLaunchArgProvider
        +-- PromptLaunchCapability + CliLaunchArgProvider
        +-- UserExtraArgsCapability + CliLaunchArgProvider
        |
        v
CliLaunchArgAssembler
        |
        +-- validate required/unsupported/conflicting contributions
        +-- sort by LaunchArgPhase and stable provider order
        +-- flatten to List<String>
        v
Final CLI argv
```

`CliSessionCapability` becomes responsible only for session lifecycle and config layout. A separate launch-argument provider collection is resolved from the same `CliToolDefinition`.

## Core interfaces

### Launch argument provider

Every capability that contributes argv implements:

```dart
abstract interface class CliLaunchArgProvider implements CliCapability {
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  );
}
```

The provider interface is intentionally capability-oriented rather than flag-oriented. A provider may emit multiple related flags and may emit nothing when its semantic condition is inactive.

### Contribution

```dart
enum LaunchArgPhase {
  command,
  session,
  workspace,
  identity,
  model,
  behavior,
  security,
  prompt,
  user,
}

class CliLaunchArgContribution {
  const CliLaunchArgContribution({
    required this.key,
    required this.phase,
    required this.args,
    this.exclusiveGroup,
  });

  final String key;
  final LaunchArgPhase phase;
  final List<String> args;
  final String? exclusiveGroup;
}
```

`key` identifies a semantic contribution, not an option string. This permits intentional repeated options such as multiple Claude `--disallowedTools` entries while still detecting duplicate semantic providers. `exclusiveGroup` is used for alternatives such as session selection modes or mutually exclusive permission policies.

### Assembler

```dart
abstract interface class CliLaunchArgAssembler {
  List<String> assemble(
    CliToolDefinition tool,
    CliLaunchContext context,
  );
}
```

The built-in assembler:

1. Collects all `CliLaunchArgProvider` capabilities from the tool definition.
2. Rejects duplicate contribution keys.
3. Rejects multiple contributions in the same exclusive group.
4. Validates provider diagnostics and unsupported requested semantics.
5. Sorts by `LaunchArgPhase`, then stable capability order.
6. Flattens token lists without shell quoting.

The existing registry API only returns the first capability of a type. The registry gains an all-matching lookup for launch assembly, for example `capabilitiesOf<T>(cli)`. Existing single-capability lookup remains for lifecycle and provider services where one implementation is expected.

## Capability groups

### Session selection

Owns fresh-session and resume semantics. It maps the same context to CLI-specific forms:

```text
Claude       --resume <id> / --session-id <id>
Codex        resume <id>
Cursor       --resume <id>
OpenCode     --session <id>
```

The Codex `resume` subcommand is emitted in `command` phase so all subsequent options are placed after it.

### Workspace access

Owns the primary working root, additional directories, path normalization, and CLI-specific representation:

```text
Claude       process cwd + --add-dir <dir>...
FlashskyAI   --dir <root> --add-dir <dir>...
Codex        --cd <root> --add-dir <dir>...
Cursor       --workspace <root> --add-dir <dir>...
OpenCode     process cwd and external-directory configuration, not argv
```

The existing `additionalDirectories` context field remains the semantic input. Codex's provider must consume it; no Codex-specific field is added.

Process cwd, remote target selection, and filesystem provisioning remain launch transport/configuration concerns. They are not incorrectly forced into argv providers.

### Team identity

`TeamBehaviorCapability` may also implement `CliLaunchArgProvider` because native team identity is part of its CLI behavior:

```text
Claude       --team-name --agent-name --agent-id
FlashskyAI   --team --member
```

The provider emits identity arguments only when `usesNativeAgentTeam` is true. Mixed TeamBus sessions do not receive native team identity flags. Codex, Cursor, and OpenCode team behavior providers emit no native team identity arguments because their current native-team capability is false.

`team.extraArgs` and `member.extraArgs` are not owned by team behavior. They belong to `UserExtraArgsCapability` and are always emitted in `user` phase.

### Model, provider, and agent

These are separate capabilities because their support differs:

- Model maps to `--model` or Codex `-m`.
- Provider may be a direct option, a provider/model composition, or configuration-only.
- Agent maps to FlashskyAI `--agent` or OpenCode `--agent`; Claude's roster agent type remains part of roster/config provisioning.

Generic option providers may be reused where the encoding is identical, but each CLI decides whether the capability is present.

### Prompt and settings

Owns CLI-visible prompt/config arguments such as Claude `--settings` and `--append-system-prompt-file`. Prompt text written into role files, MCP setup, and provider config remain in their existing configuration capabilities and are not duplicated into argv.

### User extra arguments

Parses `team.extraArgs` followed by `member.extraArgs` using the existing argument splitter and emits both in `user` phase. This is intentionally last so built-in capabilities have deterministic precedence and user arguments remain an explicit escape hatch.

## Permission model

The boolean `dangerouslySkipPermissions` is replaced as the launch semantic source of truth by orthogonal policy values:

```dart
enum LaunchApprovalPolicy {
  cliDefault,
  ask,
  autoApprove,
  never,
}

enum LaunchSandboxPolicy {
  cliDefault,
  readOnly,
  workspaceWrite,
  fullAccess,
}

enum LaunchHookTrustPolicy {
  cliDefault,
  trustedOnly,
  bypass,
}

class LaunchSecurityPolicy {
  const LaunchSecurityPolicy({
    this.approval = LaunchApprovalPolicy.never,
    this.sandbox = LaunchSandboxPolicy.fullAccess,
    this.hookTrust = LaunchHookTrustPolicy.bypass,
  });

  static const fullAccess = LaunchSecurityPolicy();
  static const cliDefault = LaunchSecurityPolicy(
    approval: LaunchApprovalPolicy.cliDefault,
    sandbox: LaunchSandboxPolicy.cliDefault,
    hookTrust: LaunchHookTrustPolicy.cliDefault,
  );

  final LaunchApprovalPolicy approval;
  final LaunchSandboxPolicy sandbox;
  final LaunchHookTrustPolicy hookTrust;
}
```

UI labels such as `auto`, `plan`, and `manual` must be mapped to explicit semantic policies before reaching a CLI provider. `plan` is not automatically treated as an approval policy; if it means plan-only interaction, it becomes a separate launch intent rather than an overloaded permission enum.

Each CLI's `PermissionLaunchCapability` maps supported policy combinations:

```text
Claude       --dangerously-skip-permissions or --permission-mode ...
Codex        --dangerously-bypass-approvals-and-sandbox
             --dangerously-bypass-hook-trust
Cursor       --force
```

If a requested policy cannot be represented by a CLI, launch preparation fails with a structured capability error. It must not silently downgrade to the CLI default.

The new policy is propagated through team member config, simple launch config, automation launch context, continue overrides, and remote SSH launch constraints. Remote constraints may reject or transform the policy before argv assembly, with an explicit warning recorded in the launch result.

## Validation and diagnostics

Launch assembly validates:

- required values for active capabilities;
- mutually exclusive session selection contributions;
- duplicate semantic contribution keys;
- unsupported workspace or security policies;
- invalid combinations such as native-team identity in mixed mode;
- missing primary workspace when a CLI requires one.

Failures use a typed `CliLaunchCapabilityException` containing the CLI, capability key, and user-facing reason. Diagnostics are logged through `AppLogger`; user-facing text is localized at the caller boundary.

## File boundaries

The refactor introduces focused launch files under `client/lib/services/cli/registry/launch/`:

- `cli_launch_arg_provider.dart`
- `cli_launch_arg_contribution.dart`
- `cli_launch_arg_assembler.dart`
- `cli_launch_capability_error.dart`
- `launch_security_policy.dart`

Each CLI keeps its capability implementations under its existing directory, for example:

- `codex/capabilities/session_selection_launch.dart`
- `codex/capabilities/workspace_access_launch.dart`
- `codex/capabilities/permission_launch.dart`
- `codex/capabilities/model_launch.dart`

The old per-CLI `capabilities/launch_args.dart` files and `CliToolAdapter.buildArguments()` are removed after migration. `CliSessionCapability` no longer owns argv construction.

## Migration sequence

1. Add contribution types, policy types, registry multi-capability lookup, assembler, and typed diagnostics.
2. Split lifecycle from launch-argument responsibilities.
3. Migrate session selection and workspace access for all five CLIs.
4. Migrate team identity, model/provider/agent, permissions, prompt/settings, and user extra arguments.
5. Replace all callers of `LaunchCommandBuilder.buildArgumentsFromContext()` with the launch assembler.
6. Remove the old adapter interface and all monolithic launch argument files.
7. Update launch previews, external terminal launch, PTY launch, SSH launch, and test fixtures to consume the same assembler.
8. Replace the boolean permission model and update persisted model serialization without legacy compatibility branches.

## Testing strategy

Unit tests cover each provider independently:

- session fresh/resume/fixed-id behavior;
- primary and additional directories, including empty values and WSL paths;
- native versus mixed team identity;
- model/provider/agent encodings;
- each supported permission policy and unsupported-policy errors;
- prompt/settings paths;
- ordering and raw extra arguments.

Assembler contract tests cover every built-in CLI and assert that the same semantic launch context produces the documented argv. Tests also assert that no unsupported capability is silently omitted.

Integration tests verify that PTY, external-terminal, SSH, and launch-preview paths all use identical assembled arguments. Existing Codex integration launch tests gain explicit assertions for `--add-dir`.

## Success criteria

- No CLI-specific monolithic `buildArguments()` remains.
- Every emitted startup argument is owned by a named launch capability.
- Codex multi-directory launches emit one `--add-dir <path>` pair per additional directory.
- Launch argument ordering is defined by the assembler, not incidental list mutation.
- Permission semantics are explicit, validated, and mapped per CLI.
- PTY, SSH, preview, and external-terminal launches share one argv assembly path.
