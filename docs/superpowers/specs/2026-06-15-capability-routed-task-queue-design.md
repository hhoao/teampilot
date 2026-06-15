# Capability-Routed Task Queue for TeamBus — Design

Date: 2026-06-15
Status: Approved (design); pending implementation plan
Scope: `client/lib/services/team_bus/` (mixed-mode shared work queue)

## Problem

In TeamBus mixed mode the leader enqueues tasks and idle workers claim them. Today
`TaskQueue.claimNext` is pure FIFO + dependency-gated: a worker is auto-handed the
lowest-`seq` claimable task with **no regard for whether that worker suits it**.
Specialized work therefore has to bypass the queue entirely (leader `send_message`
point-to-point), and a worker that auto-claims an unsuitable task can only abandon it
via `failed`/`cancelled`.

We want: **members efficiently claim tasks suited to them**, while preserving the two
structural advantages TeamBus already has over Claude Code's native swarm:

1. **Atomic, lock-free claiming** — the whole bus runs in one Dart isolate, so
   `claimNext` is a synchronous, no-`await` map mutation; two workers can never grab the
   same task and no lockfile is needed.
2. **No task left unclaimed** — `addTasks` actively wakes / cold-starts workers
   (`_engageWorkersForQueue`), unlike CC which leaves a task `pending` until the leader
   manually spawns someone.

This design is written for the **optimal architecture** with no backward-compatibility
or migration constraints.

## Decisions (locked)

| Decision | Choice |
|----------|--------|
| Suitability model | **Capability tag-set matching** (deterministic, zero-latency, pure-function) |
| Dispatch model | **Hybrid**: system auto-routes (push) **and** workers may self-pick from a filtered board (pull) |
| No eligible/idle member | **Tiered degradation + active engagement**: reserve → engage eligible → widen caps → open to all |

## Core model

### Capabilities as a first-class concept

- **Member declares capabilities.** `TeamMemberConfig` gains
  `capabilities: Set<String>` (e.g. `{frontend, react, test}`), surfaced into
  `TeammateRosterProfile.capabilities`. When empty, capabilities are **derived** from
  `agentType` (then `agent`) so role names participate in matching by default.
- **Task declares requirements.** `TeamTask` / `TeamTaskDraft` gain:
  - `requiredCapabilities: Set<String>` — **hard filter**, subset semantics:
    a member is eligible iff `member.capabilities ⊇ task.requiredCapabilities`.
    Empty set ⇒ anyone eligible (fungible work; equals today's behavior).
  - `preferredCapabilities: Set<String>` — **soft ranking** among eligible members:
    `score = |member.capabilities ∩ task.preferredCapabilities|`; ties broken by FIFO `seq`.
  - `preferredAssignee: String?` — named-member first dibs (drives Stage 0 below).

### Eligibility & scoring

```
eligible(memberCaps, task, stage) =
    dependenciesSatisfied(task)
    && stageAllows(memberId, task, stage)        // see RoutingPolicy
    && memberCaps ⊇ effectiveRequiredCaps(task, stage)

score(memberCaps, task) = |memberCaps ∩ task.preferredCapabilities|
```

`effectiveRequiredCaps` narrows/relaxes with the routing stage (Stage 2 relaxes the
hard requirement to `preferredCapabilities`; Stage 3 relaxes to ∅).

## Claiming: push and pull over one predicate

The architectural keystone: **auto-dispatch and self-pick share the same `eligible()`
predicate and the same synchronous atomic claim**, so they can never conflict and the
lock-free invariant is preserved.

### Push (system auto-route)

`TeamBus.receiveWork` continues to prioritize messages, then calls
`TaskQueue.claimNext(memberId, memberCaps)`. `claimNext` now:

1. Filters candidate tasks by `eligible(memberCaps, task, task.stage)`.
2. Orders the eligible set by `(score desc, seq asc)`.
3. Atomically claims the first (synchronous, no `await`).

An idle worker therefore only ever auto-claims tasks it is eligible for. Tasks it cannot
do are skipped; if nothing is eligible it stays idle and reports idle to the leader
(existing `_announceWorkerIdleToLead` path), surfacing the gap.

### Pull (worker self-pick)

New MCP tool `claim_task(task_id)`. A worker browses `list_tasks` — whose output now
annotates each task with `eligible_for_you: bool` and `match_score: int` — and explicitly
claims a specific **eligible** task via `claimSpecific(taskId, memberId, memberCaps)`,
guarded by the same `eligible()`. This gives the model judgment room ("I'll take the
harder one") while the system still enforces eligibility.

Both paths funnel into one private synchronous routine that selects-and-marks within a
single microtask. No `await` between read and write ⇒ still atomic, still lock-free.

## Tiered degradation (liveness guarantee)

Each task carries a `RoutingPolicy { stage, escalatedAt, reserveWindowMs, widenAfterMs,
openAfterMs }`. A `reconcile(now, liveCapsByMember)` operation advances the **monotonic**
(never-narrowing) stage. It is driven event-style on enqueue / member-idle / member-exit,
plus a lightweight timer as a backstop.

```
Stage 0 Reserved   : preferredAssignee set ⇒ only that member eligible, for reserveWindowMs (~45s)
Stage 1 Matched    : open to members whose capabilities ⊇ requiredCapabilities
Stage 2 Widened    : after widenAfterMs with no claim AND no eligible LIVE member
                     ⇒ effectiveRequiredCaps relaxes to preferredCapabilities
Stage 3 Open        : after openAfterMs ⇒ anyone may claim (fungible fallback)
```

**Engagement before degradation.** `_engageWorkersForQueue` is upgraded to be
**capability-aware**: when an enqueued task needs cap X, it preferentially doorbells (if
`atPrompt`) or cold-starts (if `declared`) a member that *has* cap X — pulling the right
person online before any requirement is relaxed. Degradation to Stage 2/3 happens only if
no eligible member can be brought online. Effective order:

```
reserve (named) → engage eligible-by-capability → widen capability requirement → open to all
```

This is strictly stronger than CC: suitability is maximized, and liveness is guaranteed
because the final stage is always fungible.

## Components (single responsibility, independently testable)

| Unit | Responsibility | Depends on |
|------|----------------|-----------|
| `TaskRouter` (new — `tasks/task_router.dart`) | **Pure functions**: `eligible(caps, task, stage)`, `score(caps, task)`, `effectiveRequiredCaps(task, stage)`, `nextStage(task, now, hasEligibleLiveMember)`. No IO, no clock of its own (clock passed in). | `TeamTask` only |
| `TeamTask` / `TeamTaskDraft` (`tasks/team_task.dart`) | Carry `requiredCapabilities`, `preferredCapabilities`, `preferredAssignee`, `routing` (RoutingPolicy). Stay immutable; mutate via `copyWith`. | — |
| `TeammateRosterProfile` (`teammate_roster_profile.dart`) | Expose `capabilities: Set<String>` with `agentType`/`agent` derivation fallback. | `TeamMemberConfig` |
| `TeamMemberConfig` (`models/team_config.dart`) | New persisted `capabilities` field (JSON encode/decode, `copyWith`). | — |
| `TaskQueue` (`tasks/task_queue.dart`) | `claimNext(memberId, caps)` + `claimSpecific(taskId, memberId, caps)` consult `TaskRouter.eligible`; `reconcile(now, liveCapsByMember)` advances stages and returns changed tasks. Still synchronous atomic claim. | `TaskRouter`, `TaskLog` |
| `TeamBus` (`team_bus.dart`) | Pass member caps into claim calls; capability-aware `_engageWorkersForQueue`; drive `reconcile` on enqueue / idle / member-exit / timer. | `TaskQueue`, member roster |
| MCP handler (`mcp/teammate_bus_mcp_handler.dart`) | `add_tasks` schema gains `required_capabilities`, `preferred_capabilities`, `preferred_assignee`, optional routing windows; `list_tasks` output annotates `eligible_for_you` + `match_score`; new `claim_task` tool. | `TeamBus` |

`TaskRouter` is the heart: a small pure module that both the push and pull paths and the
reconcile loop call, so all routing logic lives in one place that can be unit-tested
exhaustively without a bus, a clock, or a filesystem.

## Data flow (enqueue → claim)

```
leader add_tasks(brief, required_caps=[backend], preferred_assignee=dev2)
  → TaskQueue.addTasks: task.stage = Reserved(dev2), escalatedAt = now
  → TeamBus._engageWorkersForQueue (capability-aware): doorbell/cold-start dev2,
        then any backend-capable declared member
  → dev2 idle loop → receiveWork → claimNext(dev2, caps)
        → TaskRouter.eligible? yes → atomic claim → TaskWork(task)
     (OR dev2's model calls claim_task(id) explicitly = pull, same guard)

If dev2 never arrives within reserveWindow:
  → reconcile(): stage → Matched → any backend-capable idle worker auto-claims

If no backend-capable live member exists and none can be brought online:
  → reconcile(): stage → Widened → Open → a fungible worker claims it (liveness)
```

## Error handling & edge cases

- **Idle worker, only ineligible tasks nearby** → stays idle, reports idle to leader
  (existing path) so the leader sees the gap.
- **push/pull race** → same synchronous map mutation; the later caller sees
  `status != pending` and gets `null` (push) / `already_claimed` (pull).
- **Member exits mid-task** → existing `release` / `reclaimExpired` returns it to
  `pending`; `reconcile` re-routes (re-engage or escalate).
- **Capability typo / unknown cap** → never matches at Stage 1, but the task still
  escalates to Open (liveness preserved), and `list_tasks` shows it long-pending so the
  leader notices. Optional: `reconcile` emits a diagnostic `BusEvent` when a task reaches
  Open via widening (signal of a routing mismatch).
- **Stage monotonicity** → stage never narrows, preventing oscillation between
  reserve/matched/open across reconcile ticks.
- **Empty `requiredCapabilities`** → eligible to all from Stage 1 (today's behavior is the
  zero-capability special case, falling out of the general model).

## Testing

- **`TaskRouter` (pure unit tests)** — subset eligibility, scoring, `effectiveRequiredCaps`
  per stage, and `nextStage` transitions with an injected clock and a
  `hasEligibleLiveMember` flag. Exhaustive; no bus/IO.
- **`TaskQueue`** (existing harness, injected `ids`/`clock`) — `claimNext` filters by caps
  and orders by score/seq; `claimSpecific` eligibility guard; `reconcile` escalation;
  atomicity (two concurrent claims, exactly one wins).
- **`TeamBus`** — capability-aware engagement targets the correct `declared` member;
  `reconcile` triggers `wake`; no-eligible → Open end-to-end fallback.
- **MCP handler** — `add_tasks` parses capability/assignee fields; `list_tasks` annotates
  `eligible_for_you`/`match_score`; `claim_task` returns success / `already_claimed` /
  `ineligible`.

## Out of scope (YAGNI)

- LLM-scored routing or member-task bidding — capability set match + leader-authored tags
  + worker self-pick judgment is sufficient.
- Capability inference from past task history.
- Cross-team / global task pools.
