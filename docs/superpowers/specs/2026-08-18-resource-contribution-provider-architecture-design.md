# Resource Contribution Provider Architecture

**Date:** 2026-08-18  
**Status:** Design implemented through Task 6; Task 7 contract/documentation closeout

## Summary

Prompt, skill, MCP, and hook support should use the same architectural shape as
the launch-argument pipeline at the conceptual level:

```text
resource sources
    -> typed contribution providers
    -> typed assemblers
    -> neutral resource set
    -> CLI capability materializer
    -> CLI-native runtime files / environment
```

The implementation must not use one generic resource abstraction for all four
kinds. Their conflict and materialization semantics are different. Instead,
each kind gets an explicit Provider, Contribution, Assembler, and CLI
Capability contract.

## Problem

`CliLaunchArgProvider` already gives launch arguments a composable contribution
model. Before this migration, Prompt, skill, MCP, and hook support had only the
consumer side of that model:

- `PromptCapability` virtualized and materialized prompt content;
- `SkillCapability` describes the target skill directory and invocation syntax;
- `McpCapability` writes neutral MCP server specs;
- `HookCapability` renders neutral hook entries.

The resource sources are still assembled in different places. Catalog skills
are resolved by `ResourceResolver`, MCP servers by `McpRegistryService`, user
hooks by `HookLibraryResolver`, managed hooks by
`HookSeatContextCompleter`, and CLI-owned prompts inside individual prompt
capabilities. This makes new sources and new CLIs require changes in several
unrelated orchestration paths.

The design separates the two axes:

1. **Source contribution:** what resources are enabled or generated for this
   launch.
2. **CLI materialization:** how one CLI consumes the final neutral resources.

## Goals

- Allow multiple independent sources to contribute to each resource kind.
- Allow synchronous in-memory providers and asynchronous catalog/filesystem
  providers through one contract.
- Allow a CLI Capability to also be a Provider when it owns built-in content.
- Allow non-CLI sources such as workspace, plugin, extension, and managed
  services to be injected without pretending to be CLI capabilities.
- Make precedence, deduplication, conflicts, and diagnostics deterministic.
- Keep CLI-specific file formats and runtime writes inside CLI capabilities.
- Use one resource provisioning coordinator for simple, native-team, mixed,
  local, WSL, and SSH launches.
- Make unsupported resources explicit errors instead of silently dropping them.

## Non-goals

- Do not merge model/provider credentials (`ProviderCapability`) with resource
  contribution providers.
- Do not make all resources use one generic `ResourceContribution<T>` model.
- Do not make Providers write files or generate CLI-specific configuration.
- Do not change the user-facing resource selection model in this design.
- Do not make native plugin installation disappear; plugin lifecycle remains a
  separate concern from plugin-provided resources.

## Architecture

### Typed source providers

Provider interfaces are independent of `CliCapability`:

```dart
abstract interface class PromptContributionProvider {
  String get providerId;

  FutureOr<Iterable<PromptContribution>> provide(
    PromptProviderContext context,
  );
}

abstract interface class SkillContributionProvider {
  String get providerId;

  FutureOr<Iterable<SkillContribution>> provide(
    SkillProviderContext context,
  );
}

abstract interface class McpContributionProvider {
  String get providerId;

  FutureOr<Iterable<McpContribution>> provide(
    McpProviderContext context,
  );
}

abstract interface class HookContributionProvider {
  String get providerId;

  FutureOr<Iterable<HookContribution>> provide(
    HookProviderContext context,
  );
}
```

`FutureOr` preserves cheap synchronous providers while permitting catalog,
plugin, remote filesystem, credential, and managed-service providers to do
asynchronous work.

The interfaces do not extend `CliCapability`. A concrete CLI capability may
implement both interfaces when appropriate, for example a Claude prompt
capability can provide Claude's built-in member prompt and materialize the
assembled prompt. Dynamic workspace, plugin, extension, and managed providers
are passed directly to the launch coordinator.

Every contribution carries provenance:

```dart
class ContributionOrigin {
  const ContributionOrigin({
    required this.providerId,
    required this.kind,
    this.sourceId,
  });

  final String providerId;
  final ResourceOriginKind kind;
  final String? sourceId;
}
```

The origin is diagnostic metadata. Providers cannot bypass the assembler's
precedence policy by assigning arbitrary numeric priority.

### Typed assemblers

Each resource kind has its own assembler:

```dart
class PromptAssembler {
  Future<PromptAssemblyResult> assemble({
    required PromptProviderContext context,
    required Iterable<PromptContributionProvider> providers,
  });
}

class SkillAssembler {
  Future<SkillAssemblyResult> assemble({
    required SkillProviderContext context,
    required Iterable<SkillContributionProvider> providers,
  });
}

class McpAssembler {
  Future<McpAssemblyResult> assemble({
    required McpProviderContext context,
    required Iterable<McpContributionProvider> providers,
  });
}

class HookAssembler {
  Future<HookAssemblyResult> assemble({
    required HookProviderContext context,
    required Iterable<HookContributionProvider> providers,
  });
}
```

Assemblers collect providers, apply the kind-specific merge rules, and return
neutral results plus structured diagnostics. They never write files, generate
scripts, or parse CLI-specific formats.

Provider execution is deterministic: registry providers are enumerated in CLI
definition order, launch-injected providers follow in explicit injection order,
and each provider's returned iterable preserves its own order. Providers may
be awaited concurrently internally, but result ordering must remain the
declared order.

### CLI capabilities as materializers

The existing capabilities remain the target-side contracts:

- `PromptCapability` materializes a final prompt document using the CLI's
  environment, file, or argument mechanism.
- `SkillCapability` describes and materializes the CLI's skill representation.
- `McpCapability` writes an assembled `List<McpServerSpec>` and merges app-level
  credentials.
- `HookCapability` renders an assembled `List<HookEntry>` into a
  `HookWriteResult`; `ManagedHookProvisioner` remains responsible for script
  writes.

The former `PromptCapability.virtualize` source contract moves to the Provider
side. A CLI prompt class
may implement both `PromptCapability` and `PromptContributionProvider`, but
the final `PromptCapability.materialize` receives the assembled document rather
than collecting sources itself.

Skill materialization should become a first-class target operation rather than
leaving the target semantics split between `ResourceProvisioningService` and
`ResourceMaterializer`. The shared materializer may remain an implementation
detail for linked directories.

## Contribution semantics

### Prompt

`PromptContribution` contains a stable id, title/content, merge role, scope,
and origin. The assembler supports `replace`, `append`, and `section` roles.
Conflicting replace contributions at the same effective layer are errors;
lower-layer content is not silently discarded without a diagnostic.

### Skill

`SkillContribution` contains a stable id, invocation name, source artifact,
optional namespace, and origin. The initial source artifact can be a canonical
directory reference, with a sealed artifact type reserved for generated or
remote-backed skills. Plugins default to namespace-isolated invocation names.
The target Capability decides whether the artifact becomes a linked directory,
merged entry, or another CLI-native representation.

### MCP

`McpContribution` contains a stable source id, an `McpServerSpec`, and origin.
The assembler keys conflicts by the target-neutral server config key. A higher
effective layer replaces a lower layer. Two different payloads at the same
layer are a hard conflict. The target Capability remains responsible for the
native JSON/TOML shape and OAuth credential merge.

### Hook

`HookContribution` wraps the existing `HookEntry` with origin and source
metadata. The assembler deduplicates by event, matcher, and action identity;
different hooks for the same event remain valid. Managed security hooks are
fail-closed if their required contribution or target event mapping is missing.
The target Capability still owns native event names, matcher support, HTTP
support, and script/config rendering.

## Precedence and failure policy

The default effective order is:

```text
managed/security > team > expert > workspace > plugin/extension
  > global catalog > CLI built-in defaults
```

Plugin resources should normally be namespace-isolated instead of relying on
precedence to override user resources. The order is interpreted by each
assembler; it is not exposed as an arbitrary integer on each contribution.

Failures are structured and include CLI, resource kind, provider id, source id,
and the original cause:

- explicitly enabled user resources prevent successful materialization when
  their provider fails;
- optional plugin/extension resources may produce warnings and continue;
- managed and security-related hooks fail closed;
- a missing target Capability is a no-op only when the assembled resource set
  is empty; otherwise it produces an unsupported-resource error.

## Launch lifecycle

Introduce a single orchestration boundary:

```dart
class CliResourceProvisioner {
  Future<ResourceProvisionReport> provision(
    CliResourceProvisionContext context,
  );
}
```

The coordinator performs the following sequence for each actual session member:

1. Resolve the effective runtime bundle and member/CLI identity.
2. Create or stage the session runtime directories.
3. Prepare source catalogs, plugin pools, credentials, extension data, and
   managed endpoints.
4. Collect four provider sets from CLI capabilities plus launch-injected
   providers.
5. Run the four typed assemblers.
6. Materialize skills, prompts, MCP, and hooks through the selected CLI
   capabilities.
7. Merge MCP app credentials and flush the launch manifest.
8. Return warnings and diagnostics to the existing session launch result.
9. Only then connect the PTY or SSH transport.

The same assembled MCP result can be materialized into the session config and
Cursor's workspace warm tier using different materialization contexts. The
source resolution is not repeated and does not fan out to unrelated CLIs.

The staged launch path is the normative path. Older session-home entry points
remain compatibility adapters for callers that do not stage resources first;
their materialization markers must prevent a second prompt/MCP write, and their
hook bridge must invoke the same HookAssembler rather than reintroducing a
source-specific merge model.

## Migration mapping

| Current code | New ownership |
|---|---|
| `ResourceResolver` + `ResourceCatalog` | `CatalogSkillContributionProvider` + `SkillAssembler` |
| `ResourceMaterializer` | shared implementation used by `SkillCapability` |
| Former `PromptCapability.virtualize` source method | CLI built-in `PromptContributionProvider` implementation |
| `PromptHubService` | `PromptAssembler` facade/coordinator integration |
| `McpRegistryService` source resolution | catalog, Smithery, extra-server, and plugin MCP Providers |
| `McpCapability.write` | unchanged target-side materializer contract |
| `HookLibraryResolver` | user-library `HookContributionProvider` |
| `HookSeatContextCompleter` | managed/extension/plugin Hook Providers |
| `HookCapability.render` | unchanged target-side renderer |
| `ManagedHookProvisioner` | unchanged script/config write stage |
| `ConfigProfileService` resource stages | delegated to `CliResourceProvisioner` |
| `ProviderCapability.materializeSessionHome` | remains model/provider session setup; resource contributions are separate interfaces |
| `PluginCapability.provision` | remains plugin installation/decomposition; plugin resource extraction may additionally implement typed Providers |

The raw `hooks` and ad hoc resource lists in launch contexts are replaced at
the new launch boundary by a typed `ResourceProviderSet`. The runtime sequence
is Provider → Assembler → neutral result → `CliResourceProvisioner` → the
selected CLI Materializer (`Capability`/`ManagedHookProvisioner`). Compatibility
fields and session-home adapters may remain for non-staged callers, but they
must delegate to the same typed Providers/Assemblers and must not collect or
materialize a second copy of the resource set.

## Testing contract

The implementation must add tests for:

1. Provider ordering and deterministic output.
2. Each kind's deduplication, precedence, and same-layer conflict behavior.
3. Async provider failures and failure policy.
4. CLI Capability materialization for every supported representation.
5. Unsupported target Capability errors when contributions are non-empty.
6. Plugin namespace isolation.
7. Hook fail-closed behavior and managed-hook diagnostics.
8. Simple, native-team, mixed, staging-manifest, WSL, and SSH filesystem paths.
9. Repeated provisioning idempotency.
10. Contract coverage ensuring every launchable CLI exposes the required target
    capability or explicitly declares that a resource kind is unsupported.

Existing CLI-specific golden tests remain valuable: they should test only the
neutral assembly result and the CLI materializer separately, rather than
requiring one large config-profile test to cover both concerns.

## Result

This design gives prompt, skill, MCP, and hook the same composability principle
as launch arguments without forcing their very different semantics into one
generic API. Adding a new source becomes adding a typed Provider; adding a new
CLI becomes implementing target Capabilities and registering any CLI-owned
Providers. The session launch path remains the single place that coordinates
the complete resource lifecycle.
