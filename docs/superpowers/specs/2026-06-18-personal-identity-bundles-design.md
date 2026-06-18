# Personal identity bundles — design

**Date:** 2026-06-18
**Status:** Approved design, pending implementation plan
**Related:** [docs/project-identity-launch-architecture.md](../../project-identity-launch-architecture.md) (project = directory, launch identity chosen at open-with). Workspace storage layout: `WorkspaceLayout` + `RuntimeLayout` in `client/lib/services/storage/`.

## Problem

Today TeamPilot has two unequal modes:

- **Team mode** — a team is a **named, reusable config bundle** (`TeamConfig`: `skillIds`/`pluginIds`/`mcpServerIds` + `members[]` + `TeamMode`) that can be launched against any directory. Its runtime is keyed by `teamId`.
- **Simple / personal mode** — a single, nameless personal `LaunchIdentity` (`teamId == ''`). Its config is **not** a reusable bundle: it lives in a per-directory `ProjectProfile` (keyed by `projectId`) and is bolted to one directory. A built-in singleton (`AppProject.defaultPersonalId`) backs it.

The asymmetry: a user cannot have several distinct single-agent setups (e.g. a "coding" identity and a "writing" identity, each with its own skills/MCP/plugins) and reuse them across directories the way they can with teams.

After the project-identity refactor, `AppProject` is already a pure directory (no `teamId`), and launch identity is chosen at open-with time via `LaunchIdentity`. This design completes that axis: it makes **personal** a first-class, multi-instance, reusable identity — a peer of teams, minus the roster.

## Goals

- Personal identities are **named, reusable config bundles** launchable against any directory, symmetric with teams.
- Each personal identity owns its own skills, plugins, MCP servers, extensions, per-tool provider/model/effort tiering, and agent config.
- The **simple path stays zero-friction**: a Default personal identity is auto-provisioned; casual users never create or name one.
- Maximal reuse of the existing **id-keyed** runtime substrate (linking, session counter, provider catalogs) — no parallel pipeline.
- Lossless migration of existing personal setups.

## Non-goals (future work)

- Renaming `TeamConfig` → `TeamIdentity` and unifying team + personal onto a single `workspace/identities/{id}/` storage directory. This design keeps team storage as-is and adds a parallel personal store; full storage unification is a later phase.
- Any remote/SSH behavior beyond what teams already do (personal identities inherit the same runtime path resolution teams use).
- Changing TeamBus, coordination policy, or multi-agent semantics.

## Chosen approach (Approach A — generalize the substrate)

A launch identity becomes a named bundle keyed by a stable `id` with a `kind` discriminator. Personal and team share a structural interface rather than living as two unrelated worlds. Personal is **not** modeled as a "team of 1" — it has no roster and never touches TeamBus; it only borrows the id-keyed runtime substrate.

Rejected alternatives (full trade-off analysis in conversation):
- **B — parallel `PersonalIdentity` with no shared interface:** lower risk but two record types/repos/cubits drift apart; the config-surface fork stays in code.
- **C — personal as a degenerate `TeamConfig` (`members: []` + flag):** least new code, but `TeamConfig` keeps team-only fields (mode, coordination) that are meaningless for personal, and team-only logic must be guarded by scattered `if (kind == personal)` checks — the special-casing AGENTS.md warns against.

## Architecture

### Model

```text
WorkspaceIdentity (interface)            // what the launcher, runtime, and config UI see
  id: String
  kind: IdentityKind { personal, team }
  display: String
  icon: ProjectIconRef
  bundle: ConfigBundle                    // skillIds, pluginIds, mcpServerIds

PersonalIdentity implements WorkspaceIdentity
  + providerIdsByTool / modelsByTool / effortsByTool   // today's ProjectProfile per-tool tiering
  + agent: ProjectAgentConfig
  (kind == personal, no members, no TeamMode)

TeamConfig implements WorkspaceIdentity   // storage unchanged; gains `kind=team` getter + bundle getters
  + members[]
  + mode: TeamMode
  + coordination
```

- `ConfigBundle` is the shared `{ skillIds, pluginIds, mcpServerIds }` surface. Extensions are **not** a field on the bundle; they remain in `ExtensionRepository` / `ExtensionCubit`, re-keyed from `teamId` to the generic `identityId`.
- `TeamConfig` is adapted to implement `WorkspaceIdentity` by adding a `kind => IdentityKind.team` getter and exposing its existing `skillIds`/`pluginIds`/`mcpServerIds` through the `ConfigBundle` interface. No change to its on-disk JSON.
- `PersonalIdentity` is a new record. It absorbs the fields `ProjectProfile` currently carries (`skillIds`, `pluginIds`, `mcpServerIds`, `providerIdsByTool`, `modelsByTool`, `effortsByTool`, `agent`).

### Launch & routing

`LaunchIdentity` generalizes from a binary (`personal` | `team(teamId)`) to a `{kind, id}` pair:

| Route `?as=` value | Meaning |
|--------------------|---------|
| `team:<teamId>` | Team mode (unchanged) |
| `personal:<personalId>` | A specific personal identity (new) |
| `personal` | Backward-compat alias → resolves to the **Default** personal identity |

- `LaunchIdentity.personal` (the old constant) is retained as a code-level alias that resolves to the default personal id at use sites.
- `SessionLifecycleService.prepareLaunch` resolves the id → `WorkspaceIdentity` → links its bundle under the identity's runtime dir → `TerminalSession.connect`. Resolution is by id and kind; no roster lookup happens for personal.
- The `AppProject.defaultPersonalId` singleton is retired. On first run, `SessionRepository` (or its successor) auto-provisions one **Default** `PersonalIdentity`. Open-with defaults to it, so the simple path is one click and the identity stays nameless to casual users.

### Storage & runtime

- **Personal records:** `workspace/personal/{personalId}/identity.json`, mirroring `teams/{teamId}/team.json`. A `PersonalIdentityRepository` owns read/write, mirroring `TeamRepository`.
- **Runtime (shared, id-keyed):** `RuntimeLayout` methods are generalized from `teamId` to `identityId` — `teamRuntimeDir`, `teamToolDir`, `teamSessionCounterFile`, `teamPluginsDir`, `teamMcpDir`, `ensureTeamInheritsApp`, etc. become identity-keyed. **On-disk folder names stay** (`teams-runtime/{id}`, `teams/` config dir unchanged for teams) to avoid a disk migration; personal ids coexist under `teams-runtime/`. Method/param renames are internal only.
- `TeamSkillLinkerService` / `TeamPluginLinkerService` take an `identityId` and link a `ConfigBundle`, regardless of kind.
- Provider catalogs (`providers/{tool}/providers.json`) are app-level and already shared; personal identities use them as teams do.

> Naming note: keeping personal ids under a folder literally named `teams-runtime/` is a deliberate, temporary trade to avoid migrating existing team runtime trees. Full folder unification (`identities-runtime/`) is deferred to the non-goal phase.

### Config UI

- One config surface driven by `WorkspaceIdentity`. The `ProjectConfigSection.personalSections` vs `teamSections` fork collapses into:
  - **Bundle sections** (`settings`, `agent`, `skills`, `plugins`, `mcp`, `extensions`) — shown for both kinds.
  - **Members** section — shown only when `kind == team`.
- Personal config edits route through a `PersonalIdentityCubit` → `PersonalIdentityRepository` → runtime relink, reusing the same write-then-relink path teams already use. The per-directory `ProjectProfileCubit` write path for bundle config is removed.

### Library / home surface

- Personal identities are listed as **peers of teams** in the workspace home and in the open-with launch dialog (`home_workspace_launch_project_dialog.dart`).
- Creating one is "New personal setup" (name + optional icon). The **Default** identity always exists and never needs to be opened or named.

## Data flow

```text
open-with dialog
  → LaunchIdentity{ kind: personal, id }           // or team
  → SessionLifecycleService.prepareLaunch
      → resolve id → WorkspaceIdentity (PersonalIdentity | TeamConfig)
      → link ConfigBundle under RuntimeLayout(identityId)
      → allocate session id / counter under identityId
  → TerminalSession.connect

config edit (skills/plugins/mcp/extensions/agent/provider tiering)
  → PersonalIdentityCubit.mutate
  → PersonalIdentityRepository.save(identity.json)
  → runtime relink (linkers, id-keyed)
```

## Migration

Existing data to migrate: one nameless personal mode, N per-directory `ProjectProfile`s, and the `defaultPersonalId` singleton. One-time, idempotent, guarded by a schema/version flag:

1. **Seed Default.** Create the **Default** `PersonalIdentity`, seeded from the legacy default personal project's `ProjectProfile` (its skills/plugins/mcp/agent/per-tool tiering).
2. **Preserve customized directories.** For any **other** directory whose personal `ProjectProfile` is non-empty / customized, create a personal identity named after that directory and record it as that directory's remembered launch default — lossless preservation.
3. **Default the rest.** Directories with empty/default personal profiles point at Default.
4. **Shrink `ProjectProfile`.** After bundle config moves to identities, `ProjectProfile`'s remaining role is per-directory `settings` only. **Open question (resolve in planning):** if nothing non-bundle remains on `ProjectProfile`, remove it; otherwise keep it scoped to directory-level settings. Flagged, not assumed.

Migration runs once (version flag), is re-entrant, and never deletes legacy data until the new records are written and verified.

## Error handling

- **Id collision on create** — reject with a surfaced, localized error; ids are generated stable + unique (mirror team id allocation).
- **Launch against a deleted identity** — fall back to the Default personal identity and surface a notice; never hard-fail the launch.
- **Deleting a personal identity referenced as a directory's remembered default** — the directory falls back to Default.
- **Deleting the Default identity** — disallowed; it is re-provisioned if missing.
- **Migration** — version-flagged so it runs once; re-entrant; non-destructive until verified.

## Testing

Unit / cubit (subprocess + filesystem mocked via constructor injection; `setUpTestAppStorage()` / `tearDownTestAppStorage()` where `AppStorage` is touched):

- `PersonalIdentity` JSON round-trip; `PersonalIdentityRepository` create/read/update/delete.
- `WorkspaceIdentity` interface conformance for both `TeamConfig` and `PersonalIdentity` (bundle getters, kind).
- Migration: legacy singleton + per-directory profiles → Default + per-directory identities; idempotency (second run is a no-op).
- `LaunchIdentity` encode/decode for `personal:<id>`, `team:<id>`, and bare-`personal` fallback.
- Launch resolution: `prepareLaunch` resolves personal id → correct runtime dir + session counter under that id.
- Config cubit ↔ repo ↔ relink for a personal identity.
- Runtime linker (`TeamSkillLinkerService` / `TeamPluginLinkerService`) with a personal `identityId`.

Golden-path manual checks (document per AGENTS.md, CI cannot cover PTY launch end-to-end):

1. Fresh install → open a directory → launches against auto-provisioned Default personal identity (no setup prompt).
2. Create a new personal setup → add a skill + an MCP server → launch a directory with it → skill/MCP present in the agent runtime.
3. Open a **second** directory with the same personal identity → same skills/MCP apply (proves reuse).
4. Existing user upgrade → prior personal setup preserved (skills/plugins/mcp intact) under Default (or a directory-named identity).

## Affected code (orientation, not exhaustive)

| Area | Path |
|------|------|
| New personal record | `client/lib/models/` (new `PersonalIdentity`, `WorkspaceIdentity`, `ConfigBundle`, `IdentityKind`) |
| Launch identity | `client/lib/models/launch_identity.dart` |
| Personal repo / cubit | `client/lib/repositories/` (new), `client/lib/cubits/` (new `PersonalIdentityCubit`) |
| Team record adapter | `client/lib/models/team_config.dart` (`kind` + bundle getters) |
| Runtime layout (id-keyed) | `client/lib/services/storage/runtime_layout.dart` |
| Linkers | `client/lib/services/.../team_skill_linker_service.dart`, `team_plugin_linker_service.dart` |
| Launch resolution | `client/lib/services/session/session_lifecycle_service.dart` |
| Default provisioning | `client/lib/repositories/session_repository.dart` (retire `defaultPersonalId`) |
| Config sections | `client/lib/pages/home_workspace/project/project_config_section.dart` |
| Config workspace | `client/lib/pages/home_workspace/project/home_workspace_project_config_workspace.dart` |
| Open-with dialog | `client/lib/pages/home_workspace/home_workspace_launch_project_dialog.dart` |
| Extensions re-key | `client/lib/repositories/extension_repository.dart`, `extension_cubit.dart` |
| Migration | new migration under `client/lib/services/storage/` or repository init |

## Open questions (resolve during planning)

1. Fate of `ProjectProfile` after bundle config moves out — remove entirely, or keep as directory-level `settings` holder?
2. Whether a directory should remember a per-directory **default** personal identity (proposed: yes, set during migration for customized directories) or always default to global Default.
3. Display/naming of auto-created per-directory identities during migration (directory basename vs explicit `Migrated: <dirname>`).
