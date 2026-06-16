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

## Phase 2 — Replicas (Deployment → Pods)

**Goal:** a type can declare `replicas: N`; N fixed identical instances run, share the type
as their routing capability, and self-balance the type's task queue.

### Model

- **`TeamMemberConfig.replicas: int`** (default `1`). The member *is* the type; `replicas`
  is the fixed pool size. `provider`/`model`/`cli`/`prompt`/`playbook`/`capabilities` are
  the shared spec every instance inherits.
- **Instance id scheme:** `replicas == 1` → instance id is the type id unchanged (full
  backward compatibility with today's single-instance members); `replicas > 1` → instance
  ids are `{typeId}-{ordinal}` for `ordinal` in `0..N-1`.
- Each instance's routing capability is `{ typeId }` (Phase 1 rule applied to the *type*,
  not the instance id), so all `builder-*` instances match `required_capabilities:
  ["builder"]`.

### Expansion point (fixed count, created at session creation)

`SessionRepository.createSession` currently emits one `SessionMemberBinding` per member
([session_repository.dart:376](../../../client/lib/repositories/session_repository.dart)):

```dart
for (final m in valid)
  SessionMemberBinding(rosterMemberId: m.id, taskId: const Uuid().v4()),
```

Becomes, expanding each type into its fixed `replicas` instances:

```dart
for (final m in valid)
  for (final instanceId in expandInstanceIds(m))   // [m.id] when replicas==1, else m.id-0..N-1
    SessionMemberBinding(rosterMemberId: instanceId, taskId: const Uuid().v4()),
```

`expandInstanceIds` is a small pure helper (testable in isolation). The same expansion is
applied wherever bindings are (re)built (`copySession`/import paths around
`session_repository.dart:673-686`).

### Runtime wiring

- **Bus declaration / launch:** the roster is driven by the session's binding list, so each
  instance is declared and launched as its own member exactly as today — its CONFIG_DIR is
  the existing `{cliTeamName}/{memberId}` leaf, its CLI `--session-id` is its binding
  `taskId`. No config-profile layout change.
- **Per-instance roster profile:** when building each instance's `TeammateRosterProfile`,
  the spec (prompt/playbook/model/cli) comes from the parent type; `capabilities = {typeId}`;
  `memberId` = instance id; `displayName` = `{typeName} #{ordinal}` for N>1.
- **Materialization:** instances follow the existing declared → materialize lifecycle. Fixed
  count means the pool is exactly N; there is **no** on-demand autoscaling range. (Whether
  a declared instance comes online eagerly or lazily is the existing lifecycle's behavior
  and is unchanged by this design.)
- **Leader's view:** `list_teammates` shows each instance (`builder-0`, `builder-1`, …) so
  the leader can still address one directly via `send_message` when needed, while
  `add_tasks` with `required_capabilities: ["builder"]` fans out across the pool.

### UI

- Member-config form (`team_config_member_section.dart`) gains a **Replicas** stepper
  (integer ≥ 1) in the advanced section. `replicas == 1` hides nothing else; `> 1` shows a
  short hint that the role runs as an interchangeable pool.
- l10n strings `memberReplicas` / `memberReplicasSubtitle` in `app_en.arb` + `app_zh.arb`;
  re-run `flutter pub get` + `gen_warmup_glyphs.dart` per repo convention.

### Persistence / compatibility

- `TeamMemberConfig.replicas` serializes only when `> 1` (omit default).
  `DiscoverableTeamMember.replicas` mirrors it for templates.
- Existing sessions: bindings are already persisted; `replicas==1` expansion is identity, so
  old single-instance sessions are unaffected. New replica counts apply to **new** sessions
  (consistent with the existing "create a new team session after changing roster" rule).

## Components (single responsibility)

| Unit | Responsibility | Phase |
|------|----------------|-------|
| `TeammateRosterProfile` | `capabilities` always includes own/type id | 1 |
| `builtin_team_templates.dart` | Quartet routes by type name; lead playbook gating | 1 |
| `TeamMemberConfig` / `DiscoverableTeamMember` | `replicas` field (default 1) | 2 |
| `expandInstanceIds(member)` (pure helper) | type → fixed instance id list | 2 |
| `SessionRepository.createSession` / copy paths | emit one binding per instance | 2 |
| instance roster-profile builder | spec from type, `capabilities={typeId}`, id=instance | 2 |
| `team_config_member_section.dart` + ARB | Replicas stepper | 2 |

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
- **Phase 2:** `expandInstanceIds` pure tests (N=1 identity; N=3 → `id-0/1/2`);
  `createSession` emits N bindings per replicated member with distinct taskIds; instance
  roster profiles carry `capabilities={typeId}`; two builder instances both eligible for a
  `["builder"]` task and exactly one claims each (atomicity preserved); widget/cubit test
  for the Replicas stepper round-trip.

## Out of scope (YAGNI)

- On-demand/elastic autoscaling (min/max ranges) — replicas is a fixed count.
- Cross-type capability pools / multi-label members — type-name routing covers the need;
  free-form capabilities remain only as the underlying mechanism.
- Per-instance distinct models/prompts — instances of a type are identical by definition.
