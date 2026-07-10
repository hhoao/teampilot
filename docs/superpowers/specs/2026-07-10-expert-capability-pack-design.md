# Expert Capability Pack & Launch Model design

**Date:** 2026-07-10  
**Status:** Approved (implementation complete)  
**Supersedes (in part):** Personal summon semantics in [2026-07-05-expert-hub-design.md](./2026-07-05-expert-hub-design.md) — experts become full capability packs; `PersonalProfile` is removed as a launch identity.

## Summary

Landing “select expert → send” and team-member connect must share one meaning: an **expert is a full capability pack** (persona + skills + plugins + MCP), not a prompt-only overlay.

Session configuration has a single merge rule:

```
SessionRuntimeBundle = merge(team > expert > workspace)
```

**Simple mode is unteamed launch** — not a parallel `PersonalProfile` identity. There is no personal launch profile kind.

No backward compatibility: remove `PersonalProfile`, personal-only launch branches, and workspace-bundle bypasses that skip expert deps.

## Goals

| Goal | Description |
|------|-------------|
| Capability pack | `DiscoverableMember` carries `skillDeps`, `pluginDeps`, `mcpDeps` plus persona |
| One merge rule | `team > expert > workspace` for skills / plugins / MCP ids |
| One launch plan | Simple and Team both produce `SessionLaunchPlan` and share prepare/connect |
| Install then bind | Missing deps install into the **app global library** only; sessions bind ids only |
| No project mutation | Expert/team resolve never writes workspace `project-config` |
| Delete PersonalProfile | Simple = no team layer; CLI preset is a dial, not an identity |

## Non-goals

- Migrating or preserving existing `PersonalProfile` documents on disk
- Expert summon chip on team-mode landing
- Fourth config layer (“user library defaults”) beyond workspace / expert / team
- Changing TeamBus / mixed-mode coordination semantics
- Per-user “personal skills library” UI formerly keyed by `PersonalProfile` — ambient enables live on the workspace; pack deps live on experts

## Problem with the current architecture

Today Personal summon:

1. Stores `AppSession.expertKey`
2. Materializes persona into `TeamMemberConfig` → `MemberRoleProvision` (role.md / AGENTS.md) ✅
3. Builds standalone launch via `PersonalProfile` + **workspace** `ConfigBundle` only ❌
4. Expert `skillDeps` install only on “add to team”, not on Landing summon ❌
5. Experts have no `pluginDeps` / `mcpDeps` ❌

So users reasonably expect “summon expert = bring the pack,” but the runtime only injects persona.

Root cause: **Simple launch is modeled as a second identity (`PersonalProfile`) with a second bundle path**, instead of “unteamed launch over Workspace + optional Expert.”

## Canonical primitives

| Primitive | Role | Persists |
|-----------|------|----------|
| **Workspace** | Project ambient environment | `project-config` → `ConfigBundle` |
| **Expert** | Atomic capability pack | Catalog / local template: persona + deps |
| **Team** | Ordered expert refs + coordination overlay | `TeamProfile.roster[]` + team `ConfigBundle` + TeamMode/CLI |
| **CLI Preset** | Launch dial (provider/model/effort/cli) | Global presets; selected per session / slot |

**Deleted:** `PersonalProfile`, `LaunchProfileKind.personal`, and the personal-only prepare path (`standaloneTeamFromPersonal`, `personalMemberForSession` as PersonalProfile adapters).

### Replacing PersonalProfile identity / runtime (required)

Deleting `PersonalProfile` also deletes the Simple-mode **identity scope**. Replacements:

| Former Personal concern | Replacement |
|-------------------------|-------------|
| `AppSession.profileId` / `personalIdentityId` | Simple: empty / omit (mode=`simple`). Team: `teamId` as today |
| `identities-runtime/{personalId}/` CLI inherit | Simple: **skip identity layer** — inherit `cli-defaults` → workspace → session only. Team: keep `identities-runtime/{teamId}/` |
| `PersonalProfile.bundle` (enabled skills/plugins/MCP) | Workspace `project-config` bundle (ambient). Expert packs supply summon/slot deps |
| `PersonalProfile.agent` | Builtin default expert (`teampilot/builtin/default`) |
| `activePresetId` / per-tool provider maps | Session/Landing `presetId` (and team slot overrides); global `CliPresets` store |
| Automations keyed by `launchProfileId` | Team: `teamId`. Simple: fixed scope key `simple` under the workspace automations file (not a profile document) |
| Home “personal” skills/plugins/MCP sections | Remove; use workspace manage + Expert Hub editor |
| Config-profile `StandaloneLaunchProfileScope` / personal ensure | Delete; Simple uses the same provision path as Team with `team=null` and `SessionLaunchPlan` |

`LaunchProfile` becomes **team-only** (`TeamProfile`). Simple is a session mode, not a profile kind.

### Expert model upgrade

```dart
DiscoverableMember {
  key, name, description, category, …
  member              // prompt, playbook, agent, cli hints, …
  skillDeps[]         // existing
  pluginDeps[]        // NEW — same shape as Team Hub PluginDependencyRef
  mcpDeps[]           // NEW — same shape as Team Hub McpDependencyRef
}
```

Resolved form:

```dart
ExpertCapabilityPack {
  member: TeamMemberConfig   // persona for MemberRoleProvision
  bundle: ConfigBundle       // installed skillIds / pluginIds / mcpServerIds
}
```

### Default persona when Simple has no expert

Stable key: **`teampilot/builtin/default`**.

- Ships as a **builtin** catalog expert (seed persona; empty deps unless we later add ambient tools).
- Users who want a custom default save/edit a **local** expert and select it on Landing (pinning a default key in landing prefs can wait).
- Unselected expert on Landing resolves to `teampilot/builtin/default`. Do not resurrect `PersonalProfile.agent`.

## Merge semantics

### `LayeredConfigBundle.merge`

```dart
LayeredConfigBundle.merge({
  ConfigBundle? team,       // null in Simple
  ConfigBundle? expert,     // always resolved for a seat (selected or default)
  required ConfigBundle workspace,
}) → ConfigBundle
```

Semantics are **union with precedence**, not replace-the-list.

For each of `skillIds`, `pluginIds`, `mcpServerIds`:

1. Start from workspace (base set, stable order)
2. Add expert ids not already present; if the same logical id appears in both, **keep the expert occurrence** (expert wins)
3. Add team ids similarly; team wins over expert/workspace for the same id

“Same logical id” = equal string id after trim (installed library id / `expectedLocalId`).

Output is deduped with stable ordering for tests and diffs.

**Invariant:** `prepareLaunch` / config-profile provision consume **only** this `SessionRuntimeBundle`. Delete `_teamWithProjectBundle` and any path that assigns workspace or team bundle directly onto the launch team without merge.

## Resolve & install pipeline

### `ExpertCapabilityResolver`

Owns **pack** resolution (deps install + persona materialization). Existing helpers:

| Existing | Role after this change |
|----------|------------------------|
| `ExpertMemberResolver` | Key → `DiscoverableMember` (unchanged) |
| `ExpertMemberMaterializer` | Persona + slot overrides → `TeamMemberConfig`; called by the resolver (no second pack path) |
| `ExpertCapabilityResolver` (new) | `preflight` / `resolve` → `ExpertCapabilityPack` (bundle + member) |

```dart
ExpertCapabilityResolver.resolve(DiscoverableMember, {slotOverrides?}) → ExpertCapabilityPack
ExpertCapabilityResolver.preflight(expertKey) → PreflightResult  // installed ids + failures
```

Steps:

1. `ExpertMemberResolver.resolve(key)` → catalog member
2. For each skill/plugin/MCP dep: if present in the **app global library**, take id; else **install into the app global library** (same installers Team Hub clone uses)
3. Build `ConfigBundle` from resolved ids
4. `ExpertMemberMaterializer` → `TeamMemberConfig` (apply slot overrides when Team)
5. Never write `project-config`, never install into `identities-runtime/`, never mutate `TeamProfile.bundle` with expert deps

**Install sink (explicit):** always the **app global** skills / plugins / MCP libraries. There is no personal-identity install target after `PersonalProfile` is gone. Team add and Simple summon share this sink.

**Failure policy:** per-dep soft fail (skip + collect); persona still applies; surface a summary toast. Missing expert key is hard fail for that summon/connect.

**When:**

| Moment | Action |
|--------|--------|
| Landing select expert / add expert to team | `preflight` — install early |
| Connect / `prepareLaunch` | `resolve` again + `LayeredConfigBundle.merge` |

## Session launch plan (per member connect)

`SessionLaunchPlan` is the sole input to `prepareLaunch` / member connect. It is **one plan per seat**, not one plan for the whole team session.

- **Simple:** session create opens one seat → one plan (`mode: simple`).
- **Team:** session may have N roster seats; the connect loop builds **N plans** (each with that slot’s `expertKey` / `member` / `runtimeBundle`).

```dart
SessionLaunchPlan {
  mode: simple | team
  workspaceId
  sessionId
  memberId              // seat id (simple stand-in or roster slot id)
  expertKey             // selected, default builtin, or slot key — always set before prepare
  teamId?               // Team only
  presetId?
  runtimeBundle         // merge result — only ConfigBundle launch reads
  member                // materialized seat (persona + overrides)
}
```

| Mode | Bundle | Member |
|------|--------|--------|
| Simple | `merge(expert > workspace)` | Selected or `teampilot/builtin/default` |
| Team (per slot) | `merge(team > expert(slot) > workspace)` | Slot expert + overrides |

No `isPersonal` / `PersonalProfile` branch in lifecycle.

## User paths

### Simple Landing

1. User picks expert → `preflight(expertKey)` → persist draft `expertKey`
2. Send message → build `SessionLaunchPlan(mode: simple, …)`
3. Resolve pack + workspace → `runtimeBundle`
4. Open session, provision role files + CLI bundle, wait PTY ready
5. `deliverUserCommandToMember(..., directToPty: true)` + `applyFirstPromptTitle`

Deep link `?expert=` preselects Simple + expert and runs the same preflight.

### Team

**Add to team:** append `TeamRosterSlot(expertKey, overrides?)` + `preflight`; do **not** copy expert deps into `TeamProfile.bundle`.

**Connect member:** resolve slot expert → merge(team > expert > workspace) → same prepare/connect pipeline as Simple (one plan per seat).

## Prompt vs bundle (split responsibilities)

| Artifact | Source | Sink |
|----------|--------|------|
| Persona | `ExpertCapabilityPack.member` | `MemberRoleProvision` → role.md / AGENTS.md / role.mdc |
| Capabilities | `SessionLaunchPlan.runtimeBundle` | CLI config-profile (skills / plugins / MCP) |

## Removals / replacements

| Remove | Replace with |
|--------|----------------|
| `PersonalProfile` + personal kind | Simple `SessionLaunchPlan` (no team layer; no identity runtime dir) |
| `_teamWithProjectBundle` | `LayeredConfigBundle.merge` |
| `standaloneTeamFromPersonal` / PersonalProfile-based `personalMemberForSession` | `ExpertCapabilityResolver` + merge |
| Landing summon that only sets `expertKey` | preflight + connect merge of full pack |
| Expert as prompt-only in Personal summon docs | This spec’s capability-pack semantics |
| Personal home bundle sections | Workspace manage + Expert Hub |

Update [2026-07-05-expert-hub-design.md](./2026-07-05-expert-hub-design.md) Personal summon section to point here (or inline a short “superseded” note) when implementing.

**Hub surface follow-through (same change set):** Expert Hub cards/editor/publish mapper must accept `pluginDeps` / `mcpDeps` (badges, edit, portable publish) — not launch-only fields.

## Testing / acceptance

- Unit: merge conflict matrix (workspace vs expert vs team) for skills, plugins, MCP — union + precedence, stable order
- Unit: resolver installs missing deps into **app global** library; does not write project-config or identity runtime
- Simple + expert: role file contains prompt; runtime bundle includes expert ∪ workspace with expert precedence
- Simple without explicit expert: `teampilot/builtin/default` persona + workspace bundle
- Team connect builds one `SessionLaunchPlan` per slot; `merge(team > expert > workspace)`
- No remaining prepareLaunch branch keyed on `PersonalProfile`; Simple skips `identities-runtime/`

## Implementation map (indicative)

| Concern | Likely path |
|---------|-------------|
| Member deps fields | `models/discoverable_member.dart` (+ registry JSON, hub UI/publish) |
| Builtin default expert | `member-hub` / builtin templates (`teampilot/builtin/default`) |
| Merge | `services/launch/layered_config_bundle.dart` (new) |
| Resolver | `services/expert_hub/expert_capability_resolver.dart` (new); wraps materializer |
| Launch plan | `services/launch/session_launch_plan.dart` (new) + lifecycle (per seat) |
| Landing submit | `workspace_session_actions.dart` / compose landing |
| Team add | `member_roster_service.dart` |
| Delete personal identity | `models/personal_profile.dart`, provisioner, cubit, config-profile personal scopes, automations keying, home personal sections |

## Open decisions (resolved in brainstorm)

| Topic | Decision |
|-------|----------|
| Expert meaning on Landing | Full pack: prompt + skills + plugins + MCP |
| Conflict policy | Union + precedence: team > expert > workspace |
| Install timing | Preflight on select/add + resolve again at connect; bind ids only |
| Install sink | App global library only (no identity install) |
| Model completeness | Add `pluginDeps` / `mcpDeps` now |
| PersonalProfile | Remove; Simple = unteamed launch; skip identity runtime layer |
| No-expert Simple persona | Builtin `teampilot/builtin/default` |
| SessionLaunchPlan cardinality | One plan per member connect (N plans for N team seats) |
