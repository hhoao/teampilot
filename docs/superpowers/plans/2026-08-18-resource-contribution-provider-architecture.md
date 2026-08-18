# Resource Contribution Provider Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace scattered prompt, skill, MCP, and hook source assembly with typed asynchronous Contribution Providers, deterministic per-kind Assemblers, and CLI-owned materializers.

**Architecture:** Keep CLI Capabilities as target-side dialect/materialization contracts. Add independent Prompt/Skill/Mcp/HookContributionProvider interfaces, neutral contribution models, and one Assembler per resource kind. A CliResourceProvisioner collects CLI-owned and launch-injected providers, assembles resources once per actual member CLI, materializes them, and returns structured diagnostics.

**Tech Stack:** Dart, Flutter, flutter_test, injected Filesystem, RuntimeLayout, CliToolRegistry, LaunchManifest, existing CLI Capability registry.

**Implementation status:** Tasks 1–6 are implemented by the commits from
`9cdf8ff3d` through `1aa6ec708`. Task 7 is the final registry-contract,
documentation, and verification closeout; compatibility session-home facades
must reuse the typed Assemblers and must not introduce a second source merge.

## Global Constraints

- Provider interfaces do not extend CliCapability; a CLI Capability may implement a Provider interface in addition to its target capability.
- Providers may read asynchronously through FutureOr, but must not write session configuration, generate scripts, or mutate shared state.
- Each resource kind has an explicit Contribution and Assembler; do not introduce a generic ResourceContribution<T> API.
- CLI-specific formats and runtime writes remain inside the corresponding CLI Capability/materializer.
- Provider order and assembler output must be deterministic.
- Explicitly enabled user resources fail launch when their provider fails; optional plugin/extension resources may warn and continue; managed/security hooks fail closed.
- A missing target Capability is a no-op only when the assembled resource set is empty; otherwise return a structured unsupported-resource error.
- Do not merge model/provider credentials (ProviderCapability) with resource contribution providers.
- Existing unrelated worktree changes belong to the user and must not be staged or modified.
- Before claiming completion, run `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`.

---

## File Map

### New shared resource contracts

- Create `client/lib/services/resource/contribution/resource_origin.dart` — source kind and provenance metadata.
- Create `client/lib/services/resource/contribution/resource_assembly_error.dart` — structured provider, conflict, and unsupported-resource errors.
- Create `client/lib/services/resource/contribution/resource_assembly_result.dart` — warnings, errors, and deterministic diagnostics.
- Create `client/lib/services/resource/providers/prompt_contribution_provider.dart` — prompt Provider interface and context.
- Create `client/lib/services/resource/providers/skill_contribution_provider.dart` — skill Provider interface and context.
- Create `client/lib/services/resource/providers/mcp_contribution_provider.dart` — MCP Provider interface and context.
- Create `client/lib/services/resource/providers/hook_contribution_provider.dart` — hook Provider interface and context.
- Create `client/lib/services/resource/resource_provider_set.dart` — launch-injected Provider groups and registry composition.
- Create `client/lib/services/resource/assemblers/prompt_assembler.dart` — prompt collection and merge rules.
- Create `client/lib/services/resource/assemblers/skill_assembler.dart` — skill collection, artifact validation, and deduplication.
- Create `client/lib/services/resource/assemblers/mcp_assembler.dart` — MCP precedence and conflict resolution.
- Create `client/lib/services/resource/assemblers/hook_assembler.dart` — hook identity deduplication and fail-closed validation.
- Create `client/lib/services/resource/cli_resource_provisioner.dart` — one per-member resource orchestration boundary.

### Existing target-side contracts and orchestration

- Modify `client/lib/services/cli/registry/capabilities/prompt_capability.dart` — separate contribution from materialization and accept an assembled prompt document.
- Modify `client/lib/services/cli/registry/capabilities/skill_capability.dart` — add target-side skill materialization.
- Modify `client/lib/services/cli/registry/cli_tool_registry.dart` — expose CLI definition capabilities that implement non-CliCapability Provider interfaces.
- Modify the five CLI prompt capability files under `client/lib/services/cli/{claude,codex,flashskyai,cursor,opencode}/capabilities/prompt.dart`.
- Modify `client/lib/services/resource/resource_kind.dart`, `resource_scope.dart`, `resource_resolver.dart`, and `resource_provisioning_service.dart` while preserving public behavior until all callers migrate.
- Modify `client/lib/services/mcp/mcp_registry_service.dart` to delegate source resolution and target writes.
- Modify `client/lib/services/cli/registry/config_profile/hook_seat_context_completer.dart` so managed hook creation is consumed by a Hook Provider.
- Modify `client/lib/services/provider/config_profile_service.dart` to delegate resource stages to `CliResourceProvisioner`.
- Modify `client/lib/services/cli/registry/prompt/prompt_hub_service.dart` to become a thin assembler/materialization facade or remove it after all call sites migrate.

### Tests

- Create `client/test/services/resource/contribution/resource_origin_test.dart`.
- Create `client/test/services/cli/registry/provider_contribution_wiring_test.dart`.
- Create `client/test/services/resource/assemblers/prompt_assembler_test.dart`.
- Create `client/test/services/resource/assemblers/skill_assembler_test.dart`.
- Create `client/test/services/resource/assemblers/mcp_assembler_test.dart`.
- Create `client/test/services/resource/assemblers/hook_assembler_test.dart`.
- Create `client/test/services/resource/cli_resource_provisioner_test.dart`.
- Modify existing Prompt, resource, MCP, Hook, plugin-chain, and launch-manifest tests only where their public call path changes.
- Modify `client/test/services/cli/registry/all_cli_prompt_provision_capability_test.dart` into a target-capability and Provider-wiring contract test.

---

## Task 1: Add provenance, diagnostics, Provider interfaces, and Provider-set composition

**Files:**
- Create the shared contract files listed above except the four Assembler files and `cli_resource_provisioner.dart`.
- Modify `client/lib/services/cli/registry/cli_tool_registry.dart`.
- Test: `client/test/services/resource/contribution/resource_origin_test.dart`.
- Test: `client/test/services/cli/registry/provider_contribution_wiring_test.dart`.

**Interfaces:**
- `ResourceProviderSet.fromRegistryAndInjected({required CliTool cli, required CliToolRegistry registry, ResourceProviderSet injected = ResourceProviderSet.empty})`.
- `CliToolRegistry.providersOf<T>(CliTool id)` returns definition capabilities implementing a non-`CliCapability` Provider interface.
- Provider interfaces expose `String get providerId` and `FutureOr<Iterable<Contribution>> provide(Context context)`.

- [ ] **Step 1: Write failing tests for provenance equality and Provider ordering**

```dart
test('provider set preserves definition order before injected providers', () {
  final registry = _registryWithCapabilities([
    const _PromptProvider('cli-a'),
    const _PromptProvider('cli-b'),
  ]);
  final set = ResourceProviderSet.fromRegistryAndInjected(
    cli: CliTool.claude,
    registry: registry,
    injected: ResourceProviderSet(
      prompts: [const _PromptProvider('runtime-a')],
    ),
  );

  expect(
    set.prompts.map((provider) => provider.providerId),
    ['cli-a', 'cli-b', 'runtime-a'],
  );
});
```

Run: `cd client && flutter test test/services/resource/contribution/resource_origin_test.dart test/services/cli/registry/provider_contribution_wiring_test.dart`

Expected: FAIL because the new contracts and registry Provider lookup do not exist.

- [ ] **Step 2: Implement origin and diagnostic models**

Define `ResourceOriginKind` with `managed`, `team`, `expert`, `workspace`, `plugin`, `extension`, `catalog`, and `cliBuiltIn`. Define `ContributionOrigin` with `providerId`, `kind`, and nullable `sourceId`. Define diagnostics with severity, resource kind, CLI, Provider id, source id, and message. Do not store arbitrary Provider priority on a contribution.

Define `ResourceAssemblyException` carrying one or more diagnostics for hard conflicts, fail-fast Provider failures, and unsupported non-empty target resources.

- [ ] **Step 3: Implement the four independent Provider interfaces and focused contexts**

Keep contexts separate. Prompt context carries CLI, launch scope, member, mixed/delegate flags, and normalized additional directories. Skill context carries resource scope, installed catalog, filesystem, and target config directory. MCP context carries scope, catalog access, extra servers, credentials, and layout. Hook context carries member, CLI, endpoints, filesystem, hooks directory, and extension/plugin inputs.

Do not create a context containing every launch field.

- [ ] **Step 4: Implement `ResourceProviderSet` and registry lookup**

```dart
class ResourceProviderSet {
  const ResourceProviderSet({
    this.prompts = const [],
    this.skills = const [],
    this.mcp = const [],
    this.hooks = const [],
  });

  final List<PromptContributionProvider> prompts;
  final List<SkillContributionProvider> skills;
  final List<McpContributionProvider> mcp;
  final List<HookContributionProvider> hooks;
}
```

Copy lists on construction. Reject duplicate `providerId` values within one resource kind with `StateError`. Add a separate unconstrained `providersOf<T>` method instead of weakening the existing single-capability lookup API.

- [ ] **Step 5: Run focused tests and commit**

Run: `cd client && flutter test test/services/resource/contribution/resource_origin_test.dart test/services/cli/registry/provider_contribution_wiring_test.dart`

Expected: PASS.

```bash
git add client/lib/services/resource/contribution client/lib/services/resource/providers client/lib/services/resource/resource_provider_set.dart client/lib/services/cli/registry/cli_tool_registry.dart client/test/services/resource/contribution/resource_origin_test.dart client/test/services/cli/registry/provider_contribution_wiring_test.dart
git commit -m "feat: add typed resource contribution providers"
```

## Task 2: Implement deterministic Prompt contributions and migration

**Files:**
- Modify `client/lib/services/cli/registry/capabilities/prompt_capability.dart`.
- Create `client/lib/services/resource/assemblers/prompt_assembler.dart`.
- Modify the five CLI prompt capability files under `client/lib/services/cli/{claude,codex,flashskyai,cursor,opencode}/capabilities/prompt.dart`.
- Modify `client/lib/services/cli/registry/prompt/prompt_hub_service.dart`.
- Test: `client/test/services/resource/assemblers/prompt_assembler_test.dart`.
- Modify the existing CLI prompt provision tests and `client/test/services/cli/registry/prompt_hub_service_test.dart`.

**Interfaces:**
- `PromptContribution` contains id, title, content, scope, merge role, and `ContributionOrigin`.
- `PromptDocument` contains the final ordered/merged sections.
- `PromptCapability.materialize(PromptMaterializeContext ctx, PromptDocument document)` remains the only target-side write entry.
- Each built-in CLI prompt capability implements both `PromptCapability` and `PromptContributionProvider`.

- [ ] **Step 1: Write failing Assembler tests**

Cover append order following Provider order; same-layer replace conflict throwing; lower-layer replace being superseded with a diagnostic; empty Providers producing an empty document; and Provider exceptions including Provider and source ids.

Run: `cd client && flutter test test/services/resource/assemblers/prompt_assembler_test.dart`

Expected: FAIL because `PromptContribution`, `PromptDocument`, and `PromptAssembler` do not exist.

- [ ] **Step 2: Move PromptSpec semantics into PromptContribution**

Preserve existing `PromptScope` and `PromptMergeRole` values. Use one canonical assembled document; do not retain a second hidden merge model in `PromptCapability`. Add the assembled document to the materialization input with an explicit named parameter.

- [ ] **Step 3: Implement `PromptAssembler`**

Collect Providers in order. If using `Future.wait`, restore indexed result order before flattening. Validate non-empty ids, preserve provenance, apply layer policy, and return `PromptAssemblyResult(document, diagnostics)`. Throw `ResourceAssemblyException` for same-layer replace conflicts and fail-fast user Provider errors.

- [ ] **Step 4: Convert each CLI prompt implementation to Provider plus materializer**

Move each former `virtualize` implementation body into `provide`. Keep CLI-specific file paths, frontmatter, environment keys, and formatting inside `materialize`. Existing tests comparing virtualized content to materialized content must compare Provider output to the materialized document.

- [ ] **Step 5: Update PromptHubService and run focused tests**

Make `PromptHubService` call `PromptAssembler` and then the selected `PromptCapability`; it must no longer ask a Capability to collect arbitrary prompt sources.

Run:

```bash
cd client && flutter test \
  test/services/resource/assemblers/prompt_assembler_test.dart \
  test/services/cli/registry/prompt_hub_service_test.dart \
  test/services/cli/config_profile/claude_prompt_provision_test.dart \
  test/services/cli/config_profile/codex_prompt_provision_test.dart \
  test/services/cli/config_profile/flashskyai_prompt_provision_test.dart \
  test/services/cli/config_profile/cursor_prompt_provision_test.dart \
  test/services/cli/config_profile/opencode_external_directories_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/prompt_capability.dart client/lib/services/resource/assemblers/prompt_assembler.dart client/lib/services/cli/registry/prompt/prompt_hub_service.dart client/lib/services/cli/claude/capabilities/prompt.dart client/lib/services/cli/codex/capabilities/prompt.dart client/lib/services/cli/flashskyai/capabilities/prompt.dart client/lib/services/cli/cursor/capabilities/prompt.dart client/lib/services/cli/opencode/capabilities/prompt.dart client/test/services/resource/assemblers/prompt_assembler_test.dart client/test/services/cli/registry/prompt_hub_service_test.dart client/test/services/cli/config_profile/*prompt_provision_test.dart
git commit -m "refactor: assemble prompts through contribution providers"
```

## Task 3: Implement Skill contributions and preserve linked-directory behavior

**Files:**
- Create `client/lib/services/resource/assemblers/skill_assembler.dart`.
- Modify `client/lib/services/cli/registry/capabilities/skill_capability.dart`.
- Modify `client/lib/services/cli/registry/resources/default_resource_capability.dart`.
- Modify `client/lib/services/resource/resource_kind.dart`, `resource_scope.dart`, `resource_resolver.dart`, and `resource_provisioning_service.dart`.
- Add catalog and plugin Skill Providers under `client/lib/services/resource/providers/`.
- Test: `client/test/services/resource/assemblers/skill_assembler_test.dart`.
- Modify existing resource resolver/materializer/provisioning and cross-mode skill parity tests.

**Interfaces:**
- `SkillContribution` contains stable id, invocation name, optional namespace, neutral `SkillArtifact`, and origin.
- `SkillCapability.materialize({required SkillMaterializeContext context, required List<SkillContribution> skills})` owns target representation.
- `CatalogSkillContributionProvider` replaces skill-specific behavior of `ResourceResolver`.

- [ ] **Step 1: Write failing Skill Assembler tests**

Cover enabled catalog skills, disabled/unknown ids being dropped with diagnostics, stable duplicate handling, plugin namespace isolation, and same-layer name conflicts. Assert repeated provisioning leaves only the desired skill set.

Run: `cd client && flutter test test/services/resource/assemblers/skill_assembler_test.dart test/services/resource/resource_provisioning_service_test.dart`

Expected: FAIL because typed Skill contributions and the Assembler do not exist.

- [ ] **Step 2: Define neutral Skill artifacts and target materialization**

Use a sealed artifact model whose first concrete case is a canonical directory source. Keep `ResourceMaterializer` as the linked-directory implementation. `DefaultSkillCapability` declares existing `skills/` and `/skill-name` behavior and delegates materialization without knowing catalog or scope selection.

- [ ] **Step 3: Implement `CatalogSkillContributionProvider` and `SkillAssembler`**

Move enabled-id filtering, catalog source path resolution, and stable ordering out of `ResourceResolver`. The Assembler must not touch disk and must return the final neutral list plus diagnostics.

- [ ] **Step 4: Convert ResourceProvisioningService to a compatibility facade**

The service may create the catalog Provider, run `SkillAssembler`, and invoke the selected `SkillCapability`, but it must not independently resolve a second skill set. Materialize catalog and plugin contributions as one assembled desired set so plugin-provided skills are not pruned by a later catalog reconciliation.

- [ ] **Step 5: Run skill and cross-mode tests**

```bash
cd client && flutter test \
  test/services/resource/assemblers/skill_assembler_test.dart \
  test/services/resource/resource_resolver_test.dart \
  test/services/resource/resource_provisioning_service_test.dart \
  test/services/provider/cross_mode_skill_parity_test.dart \
  test/services/provider/leaf_skills_real_directory_test.dart \
  test/services/provider/personal_skill_provisioning_repro_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/resource client/lib/services/cli/registry/capabilities/skill_capability.dart client/lib/services/cli/registry/resources/default_resource_capability.dart client/test/services/resource client/test/services/provider/cross_mode_skill_parity_test.dart client/test/services/provider/leaf_skills_real_directory_test.dart client/test/services/provider/personal_skill_provisioning_repro_test.dart
git commit -m "refactor: assemble skills through contribution providers"
```

## Task 4: Implement MCP contributions, precedence, and target reuse

**Files:**
- Create `client/lib/services/resource/assemblers/mcp_assembler.dart`.
- Create MCP Providers under `client/lib/services/resource/providers/` for catalog ids, extra servers, Smithery auth application, and plugin-provided servers.
- Modify `client/lib/services/mcp/mcp_registry_service.dart` to delegate source resolution and target writes.
- Keep CLI MCP files under `client/lib/services/cli/{claude,codex,cursor,flashskyai,opencode}/capabilities/mcp.dart` focused on target format behavior.
- Test: `client/test/services/resource/assemblers/mcp_assembler_test.dart`.
- Modify MCP registry, Smithery, credential-store, and CLI writer tests where the call path changes.

**Interfaces:**
- `McpContribution` contains source id, `McpServerSpec`, and origin.
- `McpAssemblyResult` contains the stable final server list and diagnostics.
- `McpAssembler.assemble` accepts `McpProviderContext` and Providers; it does not accept a target Capability.
- `McpCapability.write` and `mergeAppCredentials` remain target-side operations.

- [ ] **Step 1: Write failing precedence and conflict tests**

Assert team overrides expert/workspace for one server key, same-layer different payloads throw, identical payloads deduplicate, catalog and extra-server ordering is stable, and Smithery credentials are applied before assembly output is materialized.

Run: `cd client && flutter test test/services/resource/assemblers/mcp_assembler_test.dart test/services/mcp/mcp_registry_service_test.dart`

Expected: FAIL because `McpContribution` and `McpAssembler` do not exist.

- [ ] **Step 2: Implement MCP contributions and `McpAssembler`**

Move `McpRegistryService._resolveSpecsFromCatalogIds` and `_resolveSpecs` source concerns into Providers. Keep server-key extraction and payload equality in the Assembler. Preserve `McpServerSpec` as the target-neutral payload.

- [ ] **Step 3: Refactor McpRegistryService into a materialization facade**

Assemble once for the requested session scope, then invoke only the requested CLI's `McpCapability`. For Cursor warm tier, reuse the assembled list with a separate output basename/context. Remove loops whose only purpose is writing unrelated CLI configurations.

- [ ] **Step 4: Preserve credential merging and stale TeamBus cleanup**

Run credential merging after target write and keep `maybeRemoveStaleProjectTeammateBus` in the coordinator/facade. Test that empty assembled input does not erase unrelated config and OAuth credentials still merge into the actual member config directory.

- [ ] **Step 5: Run MCP tests and commit**

```bash
cd client && flutter test \
  test/services/resource/assemblers/mcp_assembler_test.dart \
  test/services/mcp/mcp_registry_service_test.dart \
  test/services/mcp/smithery_mcp_auth_test.dart \
  test/services/mcp/mcp_credentials_store_test.dart \
  test/services/cli/registry/mcp_writers/mcp_config_writers_test.dart
```

Expected: PASS.

```bash
git add client/lib/services/resource/assemblers/mcp_assembler.dart client/lib/services/resource/providers client/lib/services/mcp/mcp_registry_service.dart client/lib/services/cli/*/capabilities/mcp.dart client/test/services/resource/assemblers/mcp_assembler_test.dart client/test/services/mcp client/test/services/cli/registry/mcp_writers/mcp_config_writers_test.dart
git commit -m "refactor: assemble MCP servers through contribution providers"
```

## Task 5: Implement Hook contributions and fail-closed rendering

**Files:**
- Create `client/lib/services/resource/assemblers/hook_assembler.dart`.
- Create user-library, managed, extension, plugin, and endpoint-backed Hook Providers under `client/lib/services/resource/providers/`.
- Modify `client/lib/services/hook/hook_library_resolver.dart` to expose Provider-friendly resolution without writing CLI config.
- Modify `client/lib/services/cli/registry/config_profile/hook_seat_context_completer.dart` so managed hook creation is consumed by a Hook Provider.
- Keep Hook Capability and `ManagedHookProvisioner` as target rendering/writing layers.
- Test: `client/test/services/resource/assemblers/hook_assembler_test.dart`.
- Modify existing Hook resolver, completer, and CLI writer tests where the public call path changes.

**Interfaces:**
- `HookContribution` contains `HookEntry), origin, and effective layer.
- `HookAssembler` returns stable entries and diagnostics; it does not render scripts.
- `HookCapability.render` remains the only CLI-specific hook renderer.

- [ ] **Step 1: Write failing Hook merge and fail-closed tests**

Cover identical managed/user entries deduplicating, distinct hooks for one event coexisting, same-identity payload conflicts, unsupported required native event mapping throwing, and managed Provider failures preventing materialization.

Run: `cd client && flutter test test/services/resource/assemblers/hook_assembler_test.dart test/services/hook/hook_library_resolver_test.dart`

Expected: FAIL because typed Hook contributions and the Assembler do not exist.

- [ ] **Step 2: Implement Hook Provider contexts and Assembler**

Use existing `HookEntry` action models. Define action identity using normalized command/script or URL plus headers, event, matcher, and policy fields. Preserve entry order after deduplication. Include Provider/source metadata in every conflict diagnostic.

- [ ] **Step 3: Convert existing Hook sources into Providers**

Wrap `HookLibraryResolver), `HookSeatContextCompleter`, extension settings hooks, plugin hooks, and agent-status/bus-idle endpoint hooks as independent Providers. Providers may read or construct entries, but must not call `ManagedHookProvisioner` or write files.

- [ ] **Step 4: Route all CLI Hook rendering through assembled entries**

Remove duplicated source assembly from the staged Claude, FlashskyAI, Codex, Cursor, and OpenCode paths. Pass assembled entries to the existing target writer and keep glue script writing in `ManagedHookProvisioner`. Non-staged session-home compatibility bridges may remain only when they reuse the same typed Assembler and are guarded by staging/materialization markers.

- [ ] **Step 5: Run Hook tests and commit**

```bash
cd client && flutter test \
  test/services/resource/assemblers/hook_assembler_test.dart \
  test/services/hook/hook_library_resolver_test.dart \
  test/services/cli/registry/config_profile/hook_seat_context_completer_test.dart \
  test/services/cli/registry/capabilities/hook_writer_test.dart \
  test/services/cli/registry/config_profile/claude_family_hook_writer_test.dart \
  test/services/cli/codex/codex_hook_writer_test.dart \
  test/services/cli/cursor/cursor_hook_writer_test.dart \
  test/services/cli/opencode/opencode_hook_writer_test.dart
```

Expected: PASS.

```bash
git add client/lib/services/resource/assemblers/hook_assembler.dart client/lib/services/resource/providers client/lib/services/hook/hook_library_resolver.dart client/lib/services/cli/registry/config_profile/hook_seat_context_completer.dart client/lib/services/cli/registry/capabilities/hook_capability.dart client/lib/services/cli/registry/hook/managed_hook_provisioner.dart client/test/services/resource/assemblers/hook_assembler_test.dart client/test/services/hook/hook_library_resolver_test.dart client/test/services/cli/registry/config_profile client/test/services/cli/*/*hook_writer_test.dart
git commit -m "refactor: assemble hooks through contribution providers"
```

## Task 6: Add CliResourceProvisioner and integrate launch staging

**Files:**
- Create `client/lib/services/resource/cli_resource_provisioner.dart`.
- Create `client/test/services/resource/cli_resource_provisioner_test.dart`.
- Create `client/test/services/cli/registry/resource_capability_wiring_test.dart` — real built-in registry target/provider contract.
- Modify `client/lib/services/provider/config_profile_service.dart`.
- Modify `client/lib/services/cli/registry/config_profile/config_profile_context.dart` to replace raw resource lists with `ResourceProviderSet`.
- Modify `client/lib/services/launch/session_connect_orchestrator.dart` only if launch results need structured diagnostics.
- Modify launch staging and provider config-profile tests only for the new orchestration path.

**Interfaces:**
- `CliResourceProvisionContext` contains actual CLI, runtime scope, target config paths, filesystem/layout, runtime bundle, member data, and injected `ResourceProviderSet`.
- `CliResourceProvisioner.provision` returns `ResourceProvisionReport` with warnings, hard diagnostics, and per-kind materialization results.
- The coordinator provisions only the requested member CLI; it must not iterate over unrelated `CliTool.values`.

- [ ] **Step 1: Write failing coordinator tests**

Test that one member CLI receives registry plus injected Providers in deterministic order, all four Assemblers run before materialization, non-empty unsupported resources fail, empty unsupported kinds no-op, and repeated provisioning is idempotent.

Run: `cd client && flutter test test/services/resource/cli_resource_provisioner_test.dart`

Expected: FAIL because `CliResourceProvisioner` does not exist.

- [ ] **Step 2: Implement the coordinator with explicit phases**

Implement phases in this order: resolve context; prepare source catalogs/plugin pools; collect/assemble; materialize skill/prompt/MCP/Hook; merge MCP credentials; return report. Keep Provider collection independent from CLI-specific writes. Use existing `LaunchManifest` filesystem injection so staging tests observe the same writes as production.

- [ ] **Step 3: Replace direct resource stages in ConfigProfileService**

Route `applySimpleSessionFilesystem`, `stageSimpleSessionLaunch`, and `stageTeamLaunch` through the coordinator. Preserve workspace inheritance, marketplace links, plugin pool preparation, extension warnings, agent-status endpoints, team-bus idle endpoints, project MCP cleanup, and `SessionHomeContribution` behavior. Remove duplicate prompt/skill/MCP/Hook collection from staged paths; retain only guarded compatibility bridges for non-staged callers.

- [ ] **Step 4: Replace raw Hook/resource fields in launch context**

Add `ResourceProviderSet resourceProviders` to the launch context and stop adding new resource-specific fields. Adapt existing callers at one boundary so downstream CLI capabilities receive assembled neutral results rather than resolving ids themselves.

- [ ] **Step 5: Run launch and staging tests**

```bash
cd client && flutter test \
  test/services/resource/cli_resource_provisioner_test.dart \
  test/services/provider/config_profile_service_simple_test.dart \
  test/services/provider/config_profile_service_lifecycle_test.dart \
  test/services/provider/config_profile_service_hooks_test.dart \
  test/services/provider/plugin_provisioning_chain_test.dart \
  test/services/provider/cross_mode_plugin_parity_test.dart \
  test/services/launch/launch_manifest_staging_test.dart \
  test/services/launch/cross_machine_manifest_paths_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/resource/cli_resource_provisioner.dart client/lib/services/provider/config_profile_service.dart client/lib/services/cli/registry/config_profile/config_profile_context.dart client/lib/services/launch/session_connect_orchestrator.dart client/test/services/resource/cli_resource_provisioner_test.dart client/test/services/provider client/test/services/launch/launch_manifest_staging_test.dart client/test/services/launch/cross_machine_manifest_paths_test.dart
git commit -m "refactor: centralize CLI resource provisioning"
```

## Task 7: Complete registry contracts, documentation, and full verification

**Files:**
- Modify `client/test/services/cli/registry/all_cli_prompt_provision_capability_test.dart`.
- Create `client/test/services/cli/registry/resource_capability_wiring_test.dart`.
- Modify `docs/cli-architecture.md` sections for Hub contracts, resource provisioning, and capability registration.
- Modify `client/lib/services/cli/registry/built_in_cli_tools.dart` only if target Capability assertions require it.

**Interfaces:**
- Every launchable CLI exposes target capabilities for each resource kind it claims to support.
- Provider wiring tests inspect CLI-owned Providers and dynamic injection.
- Documentation distinguishes `ProviderCapability` (model/provider credentials) from `*ContributionProvider` (runtime resource source).

- [x] **Step 1: Add registry contract tests**

For every launchable CLI, assert target Capability presence or an explicit unsupported declaration. Assert Provider ids are unique per resource kind and registration order is stable. Assert a Capability may implement both target and Provider interfaces without requiring dynamic Providers to enter the registry.

Run: `cd client && flutter test test/services/cli/registry/resource_capability_wiring_test.dart test/services/cli/registry/all_cli_prompt_provision_capability_test.dart`

Expected: PASS once the built-in registry exposes the migrated target/provider contract.

- [x] **Step 2: Update architecture documentation**

Document the source-provider → assembler → materializer pipeline, four explicit contracts, precedence/failure rules, and per-member-only provisioning. Remove statements describing `PromptCapability.virtualize` as the source contract.

- [ ] **Step 3: Run focused all-CLI tests**

```bash
cd client && flutter test \
  test/services/cli/registry/resource_capability_wiring_test.dart \
  test/services/cli/registry/all_cli_prompt_provision_capability_test.dart \
  test/services/cli/claude_launch_capabilities_test.dart \
  test/services/cli/codex_launch_capabilities_test.dart \
  test/services/cli/cursor_launch_capabilities_test.dart \
  test/services/cli/flashskyai_launch_capabilities_test.dart \
  test/services/cli/opencode_launch_capabilities_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run repository verification**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```

Expected: analyzer exits 0 and the non-integration test suite exits 0. Any pre-existing unrelated failure must be recorded with exact test name and output before claiming completion.

- [ ] **Step 5: Commit documentation, contract tests, and in-scope contract fixes**

```bash
git add client/lib/services/resource/cli_resource_provisioner.dart client/test/services/resource/contribution/resource_origin_test.dart client/test/services/cli/registry/resource_capability_wiring_test.dart docs/cli-architecture.md docs/superpowers/specs/2026-08-18-resource-contribution-provider-architecture-design.md docs/superpowers/plans/2026-08-18-resource-contribution-provider-architecture.md client/lib/services/cli/registry/built_in_cli_tools.dart
git commit -m "test: verify resource capability provider contracts"
```

## Self-review checklist

- [ ] Every spec goal maps to a task: typed async Providers (Task 1), independent Assemblers (Tasks 2–5), CLI materialization boundary (Tasks 2–6), unified launch coordinator (Task 6), deterministic diagnostics and precedence (Tasks 1–5), and registry/test documentation (Task 7).
- [ ] No task requires a generic ResourceContribution<T> abstraction.
- [ ] No task makes ProviderCapability responsible for prompt, skill, MCP, or hook source assembly.
- [ ] Prompt, Skill, MCP, and Hook each have explicit tests for ordering, deduplication, conflicts, failures, and target materialization.
- [ ] Staging, cross-machine paths, simple mode, native team mode, and mixed mode remain covered.
- [ ] The plan contains no unresolved placeholders or unspecified implementation step.
