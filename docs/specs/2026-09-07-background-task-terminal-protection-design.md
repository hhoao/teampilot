# Background Task Terminal Protection Design

Date: 2026-09-07
Status: Approved (design phase, v2 — seat lease architecture)

## Problem

Claude Code can run shell commands in the background (`Bash` with
`run_in_background: true`). The tool call returns immediately, the model
finishes its reply, and the turn ends (`Stop` → attention `done`) while the
background process keeps running under the CLI process. TeamPilot's idle
terminal reclaim (`TabMemberReclaimWatch` + `TerminalReclaimPolicy`, default
on, 180 s) then sees a quiet, unprotected terminal and discards it —
`discardMemberTerminal` → `shell.disconnect()` kills the PTY, the CLI, and
every background child process with it.

Default configuration (reclaim on, Chat view shown, member not the lead,
session not pinned, no unread inbox) therefore kills **any background task
that outlives its starting turn by more than the reclaim threshold**. The
conversation can be resumed lazily (`--resume`), but the running task is
lost.

## Verified behavior (experiment, 2026-09-07)

Isolated `CLAUDE_CONFIG_DIR`, project-level hooks.json logging every hook
event, `claude 2.1.156` driven in stream-json persistent mode (the mode that
matches an interactive TeamPilot terminal). Task: `ping -n 12 127.0.0.1`
(~11 s) via `run_in_background`.

```
UserPromptSubmit            (real user prompt)
PreToolUse  Bash            tool_input.run_in_background=true, tool_use_id
PostToolUse Bash            fires at TOOL RETURN (duration_ms≈2s, task still
                            running); carries tool_response.backgroundTaskId
Stop                        turn 1 ends; ping still running  ← kill window
  ── quiet: no PTY output, attention done, nothing protects ──
UserPromptSubmit            re-invocation; prompt is machine-parseable:
                            <task-notification>
                              <task-id>{backgroundTaskId}</task-id>
                              <tool-use-id>{tool_use_id}</tool-use-id>
                              <output-file>…</output-file>
                              <status>completed</status>
                              <summary>…</summary>
                            </task-notification>
PreToolUse/PostToolUse Read (model reads the output file)
Stop                        turn 2 ends
```

Facts this design relies on:

1. **Start signal** — `PreToolUse` (Bash) with
   `tool_input.run_in_background: true` and `tool_use_id`.
2. **Completion signal** — the re-invocation fires `UserPromptSubmit` whose
   `prompt` is a `<task-notification>` block carrying the matching
   `<tool-use-id>` (and `<task-id>` = `backgroundTaskId` from the
   PostToolUse response). `<status>` distinguishes `completed` / failed.
3. **`PostToolUse` must NOT be treated as completion**: it fires at tool
   return in interactive mode but at task completion in `-p` mode (measured
   `duration_ms` 2 031 vs 9 147 for the same command). Its timing is
   mode-dependent; use it only as the `backgroundTaskId` source.
4. All three events already flow through TeamPilot's managed hook ingress —
   `ClaudeFamilyAgentStatusNormalizer` already parses `tool_input` and
   `prompt` for `PreToolUse` / `PostToolUse` / `UserPromptSubmit`. No new
   hook registration is required.

## Goals

- A member terminal holding a live "the CLI process must survive" lease is
  never reclaimed.
- The lease model is a **first-class concept independent of attention
  semantics** (working / waiting / done): a done seat can hold leases. New
  lease sources (subagents, scheduled wakeups, workflows, future CLI-native
  signals) plug in without touching `AgentAttentionCubit` or the reclaim
  watch.
- Leases ride the existing runtime-event pipeline (gateway → projection →
  state owner), so idempotent delivery, journaling, and SSH hook tunnels
  apply for free.
- Per-seat precision: leases are keyed `(sessionId, memberId)`, not
  session-wide.

## Non-goals

- No new hook events written to CLI configs (events already arrive).
- No changes to reclaim threshold, protection-set order, or discard
  mechanics beyond one new snapshot field.
- No persistence/journal replay of leases: PTYs do not survive app restarts
  today, so an in-memory registry is sufficient (journal replay becomes
  relevant only if terminals ever survive restarts — open item).
- v1 delivers `backgroundTask` leases for the Claude family
  (claude + flashskyai, experiment-verified on claude; codex rides the same
  normalizer but its background-exec payloads are unverified — unmatched
  payloads are inert).
- No sidebar / History UI changes: the spinner keeps its attention-only
  semantics. (A "background work in flight" badge is a natural follow-up
  once the state exists; deliberately out of scope.)

## Design

### Why a separate lease model (v1 → v2)

The first draft hung `pendingBackgroundTaskIds` on
`AgentSeatAttentionEntry` next to `activeSubagentIds`. That conflates two
different questions the state currently answers at once:

- **Attention** — "does the seat need the operator / is it mid-turn?"
  (drives permission cards, ask cards, the spinner).
- **Liveness** — "must the underlying process survive?" (drives reclaim
  protection; tomorrow: other resource decisions).

`sessionIsAgentActive` feeding both the sidebar indicator and the reclaim
protection arm is exactly this conflation. Splitting them gives each
consumer an honest signal, keeps `agent_attention_cubit.dart` (already 590
lines, dense with sticky-permission edge cases) out of the blast radius, and
makes the next lease source a data change instead of a cubit change. The
`activeSubagentIds` TTL-exemption precedent shows the pattern works inside
attention; this design promotes it to its own owner instead of adding a
second special case beside it.

### Lease model

New file: `client/lib/services/agent_status/seat_lease.dart`.

```dart
/// Why a seat's underlying CLI process must stay alive beyond the
/// attention turn. A `done` seat can hold leases.
enum SeatLeaseKind { backgroundTask }

/// One keep-alive hold on a seat's CLI process.
class SeatLease extends Equatable {
  final SeatLeaseKind kind;
  final String id;            // pairing key (the starting tool_use_id)
  final DateTime acquiredAt;
}

/// Safety net for leases whose terminal event never arrives
/// (CLI crash before re-invocation, task killed, hook POST lost).
/// Event-paired leases normally clear long before this.
Duration seatLeaseTtl(SeatLeaseKind kind) => switch (kind) {
      SeatLeaseKind.backgroundTask => Duration(minutes: 60),
    };
```

New lease kinds (subagent, wakeup, workflow) extend the enum + TTL map and
add transitions in the projection — nothing else changes.

### State owner

New file: `client/lib/cubits/seat_lease_cubit.dart`
(pattern: `AgentAttentionCubit` — Equatable state, injected clock, 1-minute
prune timer):

```dart
class SeatLeaseState extends Equatable {
  final Map<String, Map<String, SeatLease>> leases; // seatKey → leaseId → lease

  bool seatHasLeases({required String sessionId, required String memberId});
  bool sessionHasLeases(String sessionId);
  SeatLeaseState pruned(DateTime now);   // drops leases past seatLeaseTtl
}

class SeatLeaseCubit extends Cubit<SeatLeaseState> {
  void acquire({sessionId, memberId, required SeatLease lease});  // idempotent per id
  void release({sessionId, memberId, required String leaseId});   // no-op when absent
  void clearSeat({sessionId, memberId});
  void clearSession(String sessionId);
  void pruneStale();   // appLogger.w when a TTL-expired lease had no terminal event
}
```

Seat key reuses `agentSeatKey` (sessionId `\0` memberId).

### Event fields (single normalization point)

`AgentStatusEvent` gains two fields, populated by
`ClaudeFamilyAgentStatusNormalizer` from parsing helpers in
`client/lib/services/agent_status/background_task_latch.dart`:

- `backgroundTaskStarted` (bool) — `hook_event_name == 'PreToolUse'`,
  `tool_name == 'Bash'`, `tool_input.run_in_background == true`, and a
  non-empty `tool_use_id` (the pairing key; events without one are ignored —
  claude always provides it).
- `taskNotificationToolUseId` (String?) — on `UserPromptSubmit`, the
  `<tool-use-id>` parsed from a `<task-notification>` prompt block; null for
  real user prompts.

### Projection

New file:
`client/lib/services/agent_runtime/seat_lease_projection.dart` —
`RuntimeEventProjection.seatLeases({required SeatLeaseCubit leases})`,
same shape as `RuntimeEventProjection.attention`: normalizes the envelope's
raw body via `ChatInteractionCapability.normalize`, then:

- `status.backgroundTaskStarted` → `acquire` (`SeatLeaseKind.backgroundTask`,
  id = `tool_use_id`).
- `status.taskNotificationToolUseId != null` → `release` (any `<status>`; a
  failed task is as finished as a completed one). Removal is a no-op when
  the lease is absent (e.g. the start hook POST was lost).

Registered in `app_shell.dart`'s `runtimeProjections` list
(`app_shell.dart:1737`), beside the attention projection. Ordering with the
attention projection is irrelevant (no shared state).

### Reclaim wiring

- `TerminalReclaimSnapshot` gains `hasActiveLeases` (bool, default false);
  `TerminalReclaimPolicy.isProtected` includes it. The protection set
  doc comment gains "live seat lease".
- `TabMemberReclaimWatch` gains a per-seat callback
  `bool Function(String sessionId, String memberId)? seatHasActiveLeases`,
  threaded through `TabSessionRuntimeCoordinator` like
  `sessionBusyFromAttention`, populated in `ChatCubit` from
  `SeatLeaseCubit.state.seatHasLeases`, injected in `app_shell.dart`.

Deliberate difference from attention: the lease arm is per-seat, not
session-wide — one member's background task must not keep a sibling
member's idle terminal alive.

### Seat lifecycle

Leases die with the seat's process, mirroring attention at the same call
sites (`client/lib/cubits/chat/session_launch_host.dart`):

- `clearAgentStatusSeat` (PTY exit, disconnect, reclaim-discard) →
  `SeatLeaseCubit.clearSeat`.
- `clearAgentStatusSessionSeats` (team-session restart, tab close) →
  `clearSession`.

On reconnect/materialize the relaunched CLI process has no surviving
children by construction, so dropping leases there is correct.

## Edge cases

- **Multiple concurrent background tasks**: each start acquires its own
  `tool_use_id`; each notification releases exactly its own. Counting down
  like `activeSubagentIds`.
- **Notification without a lease**: release is a no-op.
- **Lease without a notification**: TTL reaps after 60 min with a warning
  log.
- **`skipPermissions`**: lease events are `working`-state, unaffected by the
  waiting-gate.
- **Task stopped by the model** (`TaskStop`/kill): notification behavior
  unverified — TTL covers it (open item).
- **Real `UserPromptSubmit` never releases** — only notification-shaped
  prompts do. This is the deliberate asymmetry vs `activeSubagentIds`'s
  `startsNewTurn` reset.
- **PTY-quiet turn end** (`clearWorkingIfWorking`): touches attention only;
  leases are untouched — cursor (the one `requiresPtyFallback` CLI) would
  need its own lease source anyway before this matters.

## Testing

- `background_task_latch.dart` unit tests: start detection (Bash ±
  `run_in_background`, other tools, missing `tool_use_id`), notification
  parsing (`<task-notification>` with/without ids, real prompts, multiline,
  failed status).
- `SeatLeaseState` / `SeatLeaseCubit` tests: acquire idempotence, release
  no-op, per-seat vs per-session queries, TTL pruning + warning, clearSeat /
  clearSession.
- Normalizer tests: new fields populated on the verified payload shapes
  (recorded above).
- Projection tests: raw envelope → acquire/release transitions (mirror the
  attention projection test setup).
- `TerminalReclaimPolicy` / `TabMemberReclaimWatch` tests: snapshot with
  `hasActiveLeases` stays protected past `idleAfter`; sibling seat without
  leases is still reclaimable.
- All tests through `dart run tool/run_tests.dart` (never raw
  `flutter test`).

## Components & files

| Change | File |
|--------|------|
| Lease model + TTL policy (new) | `client/lib/services/agent_status/seat_lease.dart` |
| Start/notification parse helpers (new) | `client/lib/services/agent_status/background_task_latch.dart` |
| State owner (new) | `client/lib/cubits/seat_lease_cubit.dart` |
| Gateway projection (new) | `client/lib/services/agent_runtime/seat_lease_projection.dart` |
| Event fields | `client/lib/services/agent_status/agent_status_event.dart` |
| Normalizer population | `client/lib/services/cli/registry/capabilities/claude_family_agent_status_normalizer.dart` |
| Snapshot + protection field | `client/lib/services/terminal/terminal_reclaim_policy.dart` |
| Per-seat lease callback | `client/lib/cubits/chat/tab_member_reclaim_watch.dart`, `tab_session_runtime_coordinator.dart`, `chat_cubit.dart` |
| Seat lifecycle clearing | `client/lib/cubits/chat/session_launch_host.dart` |
| Composition + injection | `client/lib/app/app_shell.dart` |

## Open items

1. `TaskStop`-killed tasks: does a `<task-notification>` still fire?
2. `ScheduleWakeup` / cron wakeups: prompt shape of the wake re-invocation;
   a `wakeup` lease kind (acquired on `PreToolUse(ScheduleWakeup)`, TTL =
   the scheduled delay) is the natural extension.
3. Codex background-exec payload parity through the shared normalizer.
4. Migrating `activeSubagentIds` into a `subagent` lease kind (pure
   refactor, no behavior change intended) once this model lands.
5. Journal replay of leases if terminals ever survive app restarts.
6. Sidebar "background work in flight" badge consuming `SeatLeaseState`.
