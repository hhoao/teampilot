# Personal identity bundles — design

**Date:** 2026-06-18
**Status:** Approved design, pending implementation plan
**Constraints:** Clean-break refactor — **no migration, no backward/forward compatibility, no legacy code paths.** Optimal architecture only.
**Related:** [docs/project-identity-launch-architecture.md](../../project-identity-launch-architecture.md) (project = directory, launch identity chosen at open-with). Workspace storage layout: `WorkspaceLayout` + `RuntimeLayout` in `client/lib/services/storage/`.

## Problem

Today TeamPilot has two unequal modes:

- **Team mode** — a team is a **named, reusable config bundle** (`TeamConfig`: `skillIds`/`pluginIds`/`mcpServerIds` + `members[]` + `TeamMode`) launchable against any directory. Runtime keyed by `teamId`.
- **Simple / personal mode** — a single, nameless personal `LaunchIdentity` (`teamId == ''`). Its config is **not** reusable: it lives in a per-directory `ProjectProfile` (keyed by `projectId`), bolted to one directory, backed by a singleton (`AppProject.defaultPersonalId`).

The asymmetry: a user cannot keep several distinct single-agent setups (e.g. a "coding" identity and a "writing" identity, each with its own skills/MCP/plugins) and reuse them across directories the way teams allow.

## Goal — one concept: `WorkspaceIdentity`

Collapse "team" and "personal" into a single first-class concept: a **named, reusable launch identity** that owns a config bundle and is launchable against any directory. A **team** is an identity with a roster; a **personal** identity is the same bundle without a roster. Both are stored, listed, configured, and launched through one unified pipeline.

This is the natural completion of the project-identity axis: `AppProject` is the *directory* (where), `WorkspaceIdentity` is the *who/how*.

## Non-goals

- TeamBus, coordination policy, and native/mixed multi-agent semantics are unchanged (team-only).
- TeamHub (discoverable team templates) stays team-only; personal templates are future work.
- Remote/SSH path resolution is inherited from the existing identity-keyed runtime; no new remote behavior.

## Model

`WorkspaceIdentity` is a **sealed** base with two subtypes sharing a `ConfigBundle`:

```text
sealed WorkspaceIdentity
  id: String                     // stable, unique
  kind: IdentityKind { personal, team }
  display: String
  icon: ProjectIconRef
  bundle: ConfigBundle           // skillIds, pluginIds, mcpServerIds

PersonalIdentity extends WorkspaceIdentity   // kind == personal
  + providerIdsByTool / modelsByTool / effortsByTool   // single-agent per-tool tiering
  + agent: ProjectAgentConfig
  (no roster, never touches TeamBus)

TeamIdentity extends WorkspaceIdentity        // kind == team  (renamed from TeamConfig)
  + members: List<TeamMemberConfig>
  + mode: TeamMode
  + coordination
```

- `ConfigBundle { skillIds, pluginIds, mcpServerIds }` is the shared enable-list surface. Extensions keep their own lifecycle in `ExtensionRepository` / `ExtensionCubit`, re-keyed from `teamId` to `identityId` (same as teams today).
- Personal is **not** a "team of 1": no `members`, no `TeamMode`, no coordination — those fields exist only on `TeamIdentity`. The sealed split keeps team-only fields off personal records entirely (no meaningless fields, no `if (kind == …)` guards on shared data).
- `TeamConfig` is **renamed** to `TeamIdentity` and reworked to extend the sealed base. There is no `TeamConfig` left in the tree.
- `PersonalIdentity` absorbs everything `ProjectProfile` carried (`skillIds`, `pluginIds`, `mcpServerIds`, `providerIdsByTool`, `modelsByTool`, `effortsByTool`, `agent`, `activePresetId`). **`ProjectProfile`, `ProjectProfileCubit`, and `ProjectProfileRepository` are deleted.**

## Storage & runtime (unified)

| Concern | Path / key |
|---------|------------|
| Identity record (both kinds) | `workspace/identities/{identityId}/identity.json` (carries `kind`) |
| Runtime tree (linking, counters) | `identities-runtime/{identityId}/…` |
| Session counter | `identities-runtime/{identityId}/session-counter.json` |
| Sessions | `workspace/projects/{projectId}/sessions/{sessionId}/…` (unchanged — keyed by directory) |

- The `teams/` config dir and `teams-runtime/` runtime dir are **renamed** to `identities/` and `identities-runtime/`. No dual-read, no symlink, no compat shim.
- `RuntimeLayout` is reworked: every `teamId`-keyed method becomes `identityId`-keyed (`identityRuntimeDir`, `identityToolDir`, `identitySessionCounterFile`, `identityPluginsDir`, `identityMcpDir`, `ensureIdentityInheritsApp`, …). `teamId` disappears from the layout API.
- `TeamSkillLinkerService` / `TeamPluginLinkerService` → `IdentitySkillLinkerService` / `IdentityPluginLinkerService`, taking an `identityId` + `ConfigBundle`.
- Provider catalogs (`providers/{tool}/providers.json`) are app-level and shared as before.

## Repository & state

- **`IdentityRepository`** (replaces `TeamRepository`) is the single source of truth for all identities of both kinds — list, read, create, update, delete. `kind` is persisted in the record.
- **`IdentityCubit`** (replaces `TeamCubit`) holds the in-memory identity list and selection. Kind-scoped UI surfaces (team roster editor vs personal config) read filtered views from it; roster editing operates only on `TeamIdentity` instances.
- `MemberPresenceCubit` / `MailboxCubit` / TeamBus remain team-only and read `TeamIdentity`.

## Launch & routing

`LaunchIdentity` is reduced to a single stable `identityId`; **kind is resolved from the loaded identity record** (the identity list is in memory, so resolution is O(1)). There is no `personal`/`team:` prefix grammar.

| Route `?as=` value | Meaning |
|--------------------|---------|
| `<identityId>` | Launch the directory against that identity; kind read from its record |

- `SessionLifecycleService.prepareLaunch` resolves `identityId` → `WorkspaceIdentity` → links its `ConfigBundle` under `identities-runtime/{identityId}` → allocates session id/counter under that id → `TerminalSession.connect`. No roster lookup for personal.
- `AppProject` gains an optional `defaultIdentityId` — the directory's remembered launch choice, set the first time it is opened. The open-with dialog preselects it; if absent, it preselects the Default personal identity.
- `AppProject.defaultPersonalId` and the personal singleton are **deleted**.

## Config UI

- One config surface driven by `WorkspaceIdentity`. `ProjectConfigSection.personalSections` / `teamSections` are removed; sections derive from kind:
  - **Bundle sections** (`settings`, `agent`, `skills`, `plugins`, `mcp`, `extensions`) — both kinds.
  - **Members** section — `TeamIdentity` only.
- Personal config edits route through `IdentityCubit` → `IdentityRepository` → identity-keyed runtime relink — the exact path teams use. The per-directory personal config write path is gone with `ProjectProfile`.

## Library / home surface

- Identities are presented as **one unified collection**, not split into Personal/Teams groups. The existing "我的团队 / My Teams" navigation is **renamed to "工作区 / Workspaces"** — matching the model name (`WorkspaceIdentity`); each row is one Workspace, with a **kind badge/icon** distinguishing a solo (personal) setup from a team.
- Open-with lists every Workspace; "New personal setup" (name + optional icon) and "New team" both create `identities/{id}` and append to the same list.

> Naming note: "workspace" is overloaded with `HomeWorkspaceShell` (the whole home container) at the code layer. The user-facing label is "Workspaces"; internally the entity stays `WorkspaceIdentity`. The home-shell types keep their names — the overload is tolerated, not resolved here.

## First-run provisioning (not migration)

On a **fresh** install with no identities, auto-provision one **Default** `PersonalIdentity` so the simple path is one click and stays nameless to casual users. This is initialization of empty state, not migration of old state — there is no old state to read.

The Default is a **normal, editable identity** (name, icon, skills, MCP, etc. all editable like any other) — it is special only in that it cannot be deleted while it is the *only* personal identity. Once a second personal identity exists, the Default loses its undeletable status.

## Data flow

```text
open-with dialog
  → LaunchIdentity{ identityId }
  → SessionLifecycleService.prepareLaunch
      → resolve identityId → WorkspaceIdentity (PersonalIdentity | TeamIdentity)
      → link ConfigBundle under identities-runtime/{identityId}
      → allocate session id / counter under identityId
  → TerminalSession.connect

config edit (skills/plugins/mcp/extensions/agent/provider tiering)
  → IdentityCubit.mutate(identity)
  → IdentityRepository.save(identities/{id}/identity.json)
  → identity-keyed runtime relink (linkers)
```

## Error handling

- **Id collision on create** — reject with a localized error; ids generated stable + unique.
- **Launch against a deleted identity** (`AppProject.defaultIdentityId` dangles) — fall back to the Default personal identity, surface a notice, never hard-fail the launch.
- **Deleting an identity referenced by a directory's `defaultIdentityId`** — clear the reference; the directory falls back to Default.
- **Deleting the only personal identity** — disallowed (the launch surface must always have at least one personal Workspace); re-provisioned if the store is somehow empty.

## Testing

Unit / cubit (subprocess + filesystem mocked via constructor injection; `setUpTestAppStorage()` / `tearDownTestAppStorage()` where `AppStorage` is touched):

- `PersonalIdentity` and `TeamIdentity` JSON round-trip; `IdentityRepository` CRUD across both kinds; `kind` persistence.
- Sealed `WorkspaceIdentity` exhaustiveness (switch over kind has no default).
- `IdentityCubit` list/select/filter-by-kind; roster mutation rejected on `PersonalIdentity`.
- `LaunchIdentity` encode/decode (single id); `prepareLaunch` resolves id → correct `identities-runtime/{id}` dir + counter; deleted-id fallback to Default.
- Config cubit ↔ repo ↔ relink for a personal identity.
- `IdentitySkillLinkerService` / `IdentityPluginLinkerService` link a bundle under a personal `identityId`.
- First-run provisioning: empty store → exactly one Default personal identity.

Golden-path manual checks (document per AGENTS.md; CI cannot cover PTY launch end-to-end):

1. Fresh install → open a directory → launches against auto-provisioned Default personal identity (no setup prompt).
2. Create a personal setup → add a skill + an MCP server → launch a directory with it → skill/MCP present in the agent runtime.
3. Open a **second** directory with the same personal identity → same skills/MCP apply (proves reuse).
4. Create a team and a personal identity → both appear as peers in home + open-with; launching each lands in the right config surface (Members only for team).

## Affected code (orientation, not exhaustive)

| Area | Path |
|------|------|
| Sealed model | `client/lib/models/` — new `WorkspaceIdentity`, `IdentityKind`, `ConfigBundle`, `PersonalIdentity`; `team_config.dart` reworked to `TeamIdentity` |
| Launch identity | `client/lib/models/launch_identity.dart` (single id) |
| Project record | `client/lib/models/app_project.dart` (+ `defaultIdentityId`, − `defaultPersonalId`) |
| Repository | `client/lib/repositories/` — `IdentityRepository` (replaces `team_repository.dart`); **delete** `project_profile_repository.dart` |
| State | `client/lib/cubits/` — `IdentityCubit` (replaces `team_cubit.dart`); **delete** `project_profile_cubit.dart` |
| Runtime layout | `client/lib/services/storage/runtime_layout.dart` (identity-keyed), `workspace_layout.dart` (`identities/`) |
| Linkers | `client/lib/services/.../identity_skill_linker_service.dart`, `identity_plugin_linker_service.dart` |
| Launch resolution | `client/lib/services/session/session_lifecycle_service.dart` |
| First-run provisioning | bootstrap (`app_shell.dart`) / `session_repository.dart` |
| Config sections / workspace | `client/lib/pages/home_workspace/project/project_config_section.dart`, `home_workspace_project_config_workspace.dart` |
| Open-with dialog | `client/lib/pages/home_workspace/home_workspace_launch_project_dialog.dart` |
| Extensions re-key | `client/lib/repositories/extension_repository.dart`, `extension_cubit.dart` |

## Resolved decisions

1. **Per-directory memory kept.** `AppProject.defaultIdentityId` is retained; open-with preselects the directory's last-used Workspace, falling back to the Default personal identity.
2. **One unified, renamed list.** No Personal/Teams split; the "My Teams" nav becomes "工作区 / Workspaces" with a per-row kind badge (see Library / home surface).
3. **Default is a normal record.** The Default personal identity is fully editable and special only in being undeletable while it is the sole personal identity.
