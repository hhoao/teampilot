# Typed Members + Replicas (Deployment/Pod model) — Design

Date: 2026-06-16
Status: Approved (design); pending implementation plan
Scope: team model (`TeamMemberConfig`), roster→instance expansion (`SessionRepository`),
TeamBus routing, team templates, member-config UI. Builds on the committed
capability-routing engine (`TaskRouter`, capability-aware `TaskQueue`/`TeamBus`).

## Problem

A TeamBus mixed-team member is a single role *and* a single running instance. Two
gaps follow:

1. **Routing is awkward.** To send implementation work only to the builder, the leader
   must hand-tag tasks with free-form capability strings and members must carry matching
   tags — extra ceremony that, for a team where each role is a singleton, is pure
   redundancy (capability == role == member). This is what let the read-only **reviewer
   auto-claim implementation tasks** off the shared FIFO queue.
2. **No horizontal scale.** You cannot say "run 3 interchangeable builders." Each role is
   exactly one process, so a deep queue of independent implementation tasks cannot be
   worked in parallel by a pool.

## Idea (user's framing): Deployment / Pod

Treat each member as a **type** (a Deployment): one role spec, replicated into N identical
**instances** (Pods). Route work to the *type*; any idle instance of that type claims the
next task — load-balanced by the existing pull queue.

| k8s | TeamPilot mapping | Existing support |
|-----|-------------------|------------------|
| Deployment (spec) | `TeamMemberConfig` (a member = a type) | `models/team_config.dart` |
| Pod (instance) | one `SessionMemberBinding{rosterMemberId, taskId}` | `models/session_member_binding.dart` |
| Pod isolation | per-instance CONFIG_DIR `{cliTeamName}/{memberId}` (mixed mode) | `cli_data_layout.dart:49-58` |
| Selector / routing | `TaskRouter.eligible` (`caps ⊇ required`) | `tasks/task_router.dart` (committed) |

**Key realization:** instance identity in the runtime is *already keyed by `memberId`*.
Replicas are "just more memberIds." No new isolation machinery is required.

## Decisions (locked)

| Decision | Choice |
|----------|--------|
| Replica count | **Fixed** — `replicas` is an exact pool size, not an autoscaling min/max range |
| Rollout | **Phased**: Phase 1 (id-as-capability + route Quartet by type — fixes the bug) then Phase 2 (replicas) |
| Routing key | The member's **`id` (= the type name)** is an implicit capability; free-form capability tags become an optional advanced detail, not the primary model |
| Compatibility | **None required.** No migration of existing sessions/roster; pick the cleanest uniform model even where it diverges from today's single-instance behavior |

> **No backward/forward compatibility.** This design optimizes for the cleanest end-state:
> no migration of existing sessions/rosters; new team sessions adopt the model. Note that
> the singleton-pod-named-after-its-type rule (`replicas == 1` → `instanceId == typeId`) is
> chosen on *architectural* merit (a sole pod is its deployment), not for compatibility —
> it happens to also make the runtime reroute non-breaking for the common case.

## How it sits on the committed engine

The capability engine (`TaskRouter`, capability-aware `claimNext`/`claimSpecific`,
tiered degradation, MCP routing fields) stays **unchanged**. This design only changes what
fills `capabilities`:

```
instance.capabilities = { type }          // type = the parent member id
task.required_capabilities = [ type ]      // leader routes to a type
→ TaskRouter.eligible: every instance of that type matches
→ the shared queue hands the next task to whichever instance is idle (load balance)
```

So "member id as capability" + "replicas" collapse capability tags into a single
user-visible concept: **the type**. Users see *type + replica count*; `capabilities` is the
mechanism underneath.

---

## Phase 1 — Member id as implicit capability (fixes the reviewer bug)

**Goal:** route by member/type name with zero new configuration, and stop the reviewer
from claiming implementation work — without yet introducing replicas.

### Changes

1. **`TeammateRosterProfile`** — a member's own `id` is always one of its capabilities:
   `capabilities = { memberId } ∪ { explicit tags }`. Replaces the current
   `agentType`/`agent` derivation (which never fires for these templates). Source of truth
   stays `TeamMemberConfig`.
2. **Superpowers Quartet template** (`builtin_team_templates.dart`) — drop the explicit
   `{implement}`/`{review}`/`{design}` tags added earlier; route by **member name**
   instead. The team-lead playbook enqueues `add_tasks` with:
   - design/plan → `required_capabilities: ["architect"]`
   - implementation → `required_capabilities: ["builder"]`
   - review → `required_capabilities: ["reviewer"]` + `depends_on` the implementation task
     ids (review unlocks only after the build is done).
   The "never leave a task untagged" instruction stays.

### Why this already fixes the bug

The reviewer's id is `reviewer`; its capabilities become `{reviewer}`. An implementation
task requires `["builder"]`. `TaskRouter.eligible("reviewer", {reviewer}, task)` → false.
The reviewer can never claim implementation work; review tasks are gated behind the build
via `depends_on`. No member-config UI or per-member tagging is needed for singleton teams.

### Out of scope for Phase 1

`replicas`, instance expansion, UI changes. (The free-form capabilities UI field explored
earlier was reverted and is intentionally **not** reintroduced here — type-name routing
covers the common case.)

---

## Phase 2 — Replicas via first-class MemberType / MemberInstance

**Goal:** a type can declare `replicas: N`; N fixed identical instances run as distinct
runtime pods, share the type as their routing capability, and self-balance the type's queue.

### Architecture: two concepts, one bridge

The decisive choice is **not** to overload `TeamMemberConfig` with id-string-encoded
instances. Instead:

- **`TeamMemberConfig` = MemberType (Deployment spec).** What is persisted in
  `TeamConfig.members` and edited in the UI. Gains `replicas: int` (default `1`). Holds the
  shared spec (`prompt`/`playbook`/`cli`/`model`/`provider`/`effort`/`capabilities`). Not
  renamed — renaming a 30+ file class adds churn, not architecture.
- **`MemberInstance` = Pod (new value type).** A lightweight runtime handle
  `{ TeamMemberConfig type, int ordinal }`. It does **not** copy the spec — it resolves
  prompt/playbook/model through `type`. `instanceId` is a computed property.
- **`expandTeamRoster(TeamConfig) → List<MemberInstance>`** is the *single* Deployment→Pod
  fan-out (pure, exhaustively testable). The runtime layer (launch loop, bus, config-profile,
  tabs) operates on `MemberInstance`s; the config/UI layer operates on `TeamMemberConfig`
  types. No other code expands replicas.

**Crucial invariant:** instances never hold their own copy of the spec. Per-instance state
(future: health, resume, affinity, metrics) gets a home on `MemberInstance`; the type stays
the spec. Switching fixed→dynamic scaling later is a change to the *expansion policy*, not
the model.

### Instance identity (singleton pod = type name)

- `instanceId`: a type with `replicas == 1` yields a single instance whose id **is the type
  id** (`builder`, `team-lead`, …) — a sole pod is named after its deployment. A type with
  `replicas > 1` yields `{typeId}-{ordinal}` for `ordinal` in `0..replicas-1`
  (`builder-0`, `builder-1`, …). This is the cleaner rule (no redundant `-0` on singletons)
  **and** it keeps every existing single-instance team and the lead byte-identical, so the
  runtime reroute lands without a breaking change to the common case.
- `displayName`: the type name for a singleton; `{typeName} #{ordinal}` when `replicas > 1`.
- **Routing capability:** `{ typeId, instanceId } ∪ type.capabilities`. `typeId` makes the
  whole pool match `required_capabilities: ["builder"]` (load-balanced); `instanceId` lets
  the leader address one pod directly (`["builder-1"]` or `send_message(to: "builder-1")`).
  Phase 1's "id is a capability" rule is exactly this with `typeId == instanceId` (singleton).

### Phase 2a — backend core (independently testable, no UI)

1. **`TeamMemberConfig.replicas: int`** (default 1; serialize when `> 1`).
   `DiscoverableTeamMember.replicas` mirrors it for templates.
2. **`MemberInstance` value type** + **`expandTeamRoster`** pure function
   (`models/member_instance.dart`).
3. **`SessionMemberBinding`** becomes `{ instanceId, typeId, taskId }` (rename
   `rosterMemberId` → `instanceId`; add explicit `typeId` so instance→type needs no string
   parsing).
4. **`SessionRepository.createSession`** (and the copy/import paths around
   `session_repository.dart:673-686`) allocate one binding per instance via
   `expandTeamRoster`:
   ```dart
   for (final inst in expandTeamRoster(team))
     SessionMemberBinding(instanceId: inst.instanceId, typeId: inst.type.id,
         taskId: const Uuid().v4()),
   ```
5. **`TeammateRosterProfile.fromInstance(MemberInstance, team, …)`** — `memberId =
   instanceId`, `capabilities = {typeId, instanceId} ∪ type.capabilities`, spec from the
   type, `displayName` per the rule. (`fromMember` becomes a thin `fromInstance` with a
   singleton instance, preserving Phase-1 behavior.)
6. **Reroute the runtime to iterate instances:**
   - **Launch loop** ([session_launch_service.dart:230](../../../client/lib/cubits/chat/session_launch_service.dart)
     `for (final candidate in team.members …) _scheduleMemberConnect`) → iterate
     `expandTeamRoster(team)`; `_scheduleMemberConnect` receives an instance identity (its
     `instanceId`) while resolving spec from the type. Config-profile CONFIG_DIR is the
     existing `{cliTeamName}/{instanceId}` leaf; CLI `--session-id` is the binding `taskId`.
   - **Bus declaration** ([tab_team_bus_coordinator.dart:94](../../../client/lib/cubits/chat/tab_team_bus_coordinator.dart))
     → iterate the session's instances (rebuilt from bindings via their `typeId`), declaring
     one `AgentNode` per instance with `fromInstance`.
   - **`forceWaitForMember` resolver** (same file) → resolve `memberId` (instanceId) to its
     type via `binding.typeId`, then `effectiveForceWaitBeforeStop`.

   Fixed count means the pool is exactly N; instances follow the existing
   declared → materialize lifecycle (no autoscaling range).

### Phase 2b — UI (separate plan)

The runtime members panel ([`widgets/right_tools/right_tools_panel.dart`] →
`MembersPanel`) already renders a **flat, selectable `List<TeamMemberConfig>`** with a
per-member presence indicator and shell, keyed by `member.id`. Phase 2a already keyed
shells / bus nodes / bindings by instance id. So pods surface with near-zero new UI by
feeding the panel instance projections instead of types.

1. **Members panel shows pods (flat rows).** In `right_tools_panel.dart`, replace the
   `team.members` list source (and the `team.members.firstWhere((m) => m.id == id)`
   selection/action lookups) with `runtimeRosterMembers(team)`. Pods render as flat rows
   `Builder #0`, `Builder #1` (singletons stay `Builder`), each with its own presence
   indicator and shell; selection/actions resolve the chosen **instance id** to its
   projection. No grouping/collapse UI (YAGNI; matches the existing flat list and k8s pod
   list intuition).
2. **Per-pod presence.** `member_presence_cubit.dart` passes `team.members` to
   `MemberPresenceService.compute`; change it to `runtimeRosterMembers(team)` so presence
   is computed per pod.
3. **Replicas stepper.** The member-config form (`team_config_member_section.dart`) gains a
   small integer **Replicas** stepper (min 1) in the advanced section, editing the type's
   `replicas`. l10n `memberReplicas`/`memberReplicasSubtitle` in `app_en.arb` + `app_zh.arb`
   (re-run `flutter pub get` + `gen_warmup_glyphs.dart`).
4. **Out of scope:** per-instance *distinct* config (instances of a type are identical by
   definition); per-instance provider isolation — already correct, because each pod launches
   with the instance projection (which carries the type's `provider`) and its own
   config-profile leaf, resolved per-launch by `resolveMemberClaudeSettings(member: <pod>)`.

### Persistence

- `TeamMemberConfig.replicas` / `DiscoverableTeamMember.replicas` serialize only when `> 1`.
- A session's roster is fixed at creation (bindings allocated + persisted then), so a later
  `replicas` change affects only **new** sessions — an inherent property, not a compat
  concession. No migration is performed.

## Components (single responsibility)

| Unit | Responsibility | Phase |
|------|----------------|-------|
| `TeammateRosterProfile` | `capabilities` always includes own/type id | 1 |
| `builtin_team_templates.dart` | Quartet routes by type name; lead playbook gating | 1 |
| `TeamMemberConfig` (= MemberType) / `DiscoverableTeamMember` | `replicas` field (default 1) | 2a |
| `MemberInstance` + `expandTeamRoster` (`models/member_instance.dart`, pure) | Deployment→Pod fan-out; `instanceId`/`displayName`/capability rule | 2a |
| `SessionMemberBinding` | `{ instanceId, typeId, taskId }` | 2a |
| `SessionRepository.createSession` / copy paths | one binding per instance via `expandTeamRoster` | 2a |
| `TeammateRosterProfile.fromInstance` | id=instanceId, caps=`{typeId,instanceId}∪explicit`, spec from type | 2a |
| launch loop / bus coordinator / forceWait resolver | iterate instances, resolve spec via type | 2a |
| `team_config_member_section.dart` + ARB; tab/sidebar pod grouping | Replicas stepper; per-instance presentation | 2b |

## Error handling & edge cases

- **`replicas < 1`** → clamp to 1 at parse/use.
- **Display-name vs id routing** → route on the stable `typeId`, never the editable display
  name (ids are slugged and stable post-create).
- **Name collision** between a type id and an unrelated capability string → acceptable; type
  ids are slugged role names, free-form tags are an advanced opt-in. Documented, not guarded.
- **Singletons** (team-lead, architect) → `replicas: 1`; expansion is identity; behavior
  identical to today.
- **Leader still hard-targets one instance** via `send_message(to: "builder-1")` when it
  must; queue routing stays type-level.

## Testing

- **Phase 1:** `TeammateRosterProfile` includes member id in capabilities; Quartet template
  asserts type-name routing + `depends_on` gating in the lead playbook; an end-to-end
  TeamBus test that a `reviewer`-capability member cannot `claimNext` a
  `required:["builder"]` task while the `builder` member can.
- **Phase 2a:** `expandTeamRoster`/`MemberInstance` pure tests (lead → canonical id;
  worker N=3 → `builder-0/1/2`; instanceId/displayName/capability rule); `createSession`
  emits N bindings per replicated type with distinct taskIds and correct `typeId`;
  `fromInstance` carries `capabilities={typeId,instanceId}∪explicit` with spec from the type;
  two builder instances both eligible for a `["builder"]` task and exactly one claims each
  (atomicity preserved); launch loop / bus coordinator declare one node per instance.
- **Phase 2b:** widget/cubit test for the Replicas stepper round-trip; pod grouping in the
  tab/sidebar.

## Out of scope (YAGNI)

- On-demand/elastic autoscaling (min/max ranges) — replicas is a fixed count.
- Cross-type capability pools / multi-label members — type-name routing covers the need;
  free-form capabilities remain only as the underlying mechanism.
- Per-instance distinct models/prompts — instances of a type are identical by definition.
