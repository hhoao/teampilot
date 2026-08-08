# Turn Completion & Working-State Clear — Design

**Date:** 2026-08-08
**Status:** Approved (design review)

## Problem

After a Cursor conversation finishes, the chat History footer keeps showing
"运行中…" (`sessionHistoryRunning`) indefinitely. The session stays in
`workingSessionIds` even though the agent has returned to its prompt.

Root cause is two-layer:

1. **Architecture layer** — `workingSessionIds` is an OR of two independent
   signals (`tab_working_aggregator.dart`):

   ```dart
   final attentionBusy = _sessionBusyFromAttention?.call(sessionId) ?? false;
   if (sessionWorking || attentionBusy) working.add(sessionId);
   ```

   The PTY-quiet → turn-end path (`MemberTurnIdleSync`) clears only the first
   (`userTurnActive` / bus turn). The second — the `AgentAttentionCubit` seat —
   is cleared only by: a CLI `done` event, an `/idle` POST, the next operator
   submit, or a 30-minute stale TTL.

2. **Cursor layer** — Cursor registers a `stop` hook
   (`cursor_home_agent_status_overlay.dart`) and `_normalizeCursor` maps
   `'stop' → done`, but in **simple mode** the `stop` event is not reliably
   delivered (see `chat_cubit.dart:811` comment "CLIs without Stop/done
   (Cursor simple)"). Meanwhile `afterAgentResponse` stamps the seat `working`,
   and nothing clears it → `sessionIsAgentActive` stays true → session stuck in
   `workingSessionIds`.

### Why other CLIs are unaffected

| CLI | done/idle signal | reliable? |
|-----|------------------|-----------|
| claude | `Stop` / `StopFailure` → done | yes (also pushed back to `wait_for_message`) |
| flashskyai | `Stop` / `StopFailure` → done | yes |
| codex | `Stop` / `StopFailure` → done | yes |
| opencode | `session.idle` → done | yes |
| cursor | `stop` → done | **no in simple mode** |

### Why integration tests missed it

The simple-mode idle/busy test group (`session_idle_busy_integration_test.dart:593`)
does **not** bind an `AgentAttentionCubit`, so `sessionBusyFromAttention`
hardcodes to false and the attention-OR path is effectively disabled in tests.
The tests drive `markUserTurnStarted` (the shell-latch path) and never simulate
Cursor's `/agent-status?event=afterAgentResponse` hook, so the seat is never
stamped `working` in the first place.

A second independent bug in **mixed mode**: the `/idle` HTTP handler writes
`idleStopDecision` but never calls `bus.onMemberIdle` (`notifyIdle` exists on
`TeammateBusMcpHandler` but has zero call sites). For a push CLI this means the
bus turn never ends → `claudeIsActive` stays true → presence stays working.

## Goals

1. "运行中" clears when the conversation ends — **done event or PTY-quiet
   fallback, whichever comes first** (先到先清), without falsely clearing
   `waiting` permission seats.
2. Model "turn completion signals" as a **CLI-declared capability** so new CLIs
   opt in with three fields.
3. Full integration coverage: **5 launch-supported CLIs × simple + mixed ×
   done/PTY-fallback/not-mis-clear**.
4. Fix the mixed-mode `/idle` → bus turn-end dead link.

Non-goals (YAGNI): changing `AgentStatusNormalizer`,
`AgentAttentionCubit.applyEvent`, `MemberTurnIdleSync`, `MemberCoordination`,
`usesPresenceSnapshotForTab`, or the `tab_working_aggregator` OR structure.
The 30-minute stale TTL stays as the ultimate backstop.

## Design

### 1. New capability: `TurnCompletionCapability`

New interface in `client/lib/services/cli/registry/capabilities/`, implemented
per CLI and added to each `CliToolDefinition.capabilities`.

```dart
/// Declares a CLI's "turn ended" signals, driving reliable session
/// working-state clearing.
abstract interface class TurnCompletionCapability implements CliCapability {
  /// Agent-status hook event names that mean "turn ended" (→ done).
  Set<String> get doneEventNames;

  /// Whether the PTY-quiet turn-end fallback may clear the seat
  /// (done event may be unreliable for this CLI).
  bool get requiresPtyFallback;

  /// Whether this is a doorbell-push CLI (mixed mode: `/idle` must end the
  /// bus turn).
  bool get usesDoorbellPush;
}
```

| CLI | doneEventNames | requiresPtyFallback | usesDoorbellPush |
|-----|---------------|--------------------|-----------------|
| claude | `{Stop, StopFailure}` | false | false |
| flashskyai | `{Stop, StopFailure}` | false | false |
| codex | `{Stop, StopFailure}` | false | false |
| opencode | `{session.idle}` | false | false |
| cursor | `{stop}` | **true** | **true** |

### 2. Three clear paths (first-wins, never clears `waiting`)

```
conversation ends → "运行中" clears
  ├─ ① done event (existing): normalizer → done → seat cleared
  ├─ ② PTY-quiet fallback (new): endTurn edge → clear working seat
  │     (only when requiresPtyFallback && no pending doorbell)
  └─ ③ /idle → bus (fix): push CLI stop hook POST /idle → notifyIdle
        → bus.onMemberIdle → TurnEnded → claudeIsActive=false
```

### 3. Component: PTY-quiet fallback (②)

New callback `onAfterTurnEnded(sessionId, memberId)` mirrors the existing
`onAfterTurnLatched`:

```
TabSessionIdleWatch.tick
  └─ MemberTurnIdleSync.tick(... endTurn: () {
        coordination.endTurn();
        onAfterTurnEnded(sessionId, memberId);   // new
     })
        ↓ threaded through TabSessionRuntimeCoordinator
ChatCubit._onTurnEnded(sessionId, memberId) {
  if (cli.requiresPtyFallback && !bus.hasPendingDoorbell) {
    attention.clearWorkingIfWorking(sessionId, memberId);
  }
}
```

New idempotent method on `AgentAttentionCubit`:

```dart
void clearWorkingIfWorking({required String sessionId, required String memberId}) {
  // reads current seat; only working → done/clear; never touches waiting
}
```

Guards:
- only `requiresPtyFallback` CLIs (currently cursor only); others no-op
- skip when the bus has a pending doorbell (`doorbelled && !inbox.isEmpty`),
  matching `shouldDeferPtyIdleEnd`, so a PTY-quiet edge never ends a turn while
  the agent is still waiting on mail
- simple mode has no bus → fallback syncs naturally with `userTurnActive` edge

### 4. Component: `/idle` → bus turn-end fix (③)

`handleIdleRequest` (`teammate_bus_mcp_http_delegate.dart`) writes the reply
then calls `handler.notifyIdle(memberId)` (which already calls
`bus.onMemberIdle`).

Safety:
- push CLI (cursor, forceWait=false): `waitingForMessage=false` →
  `onMemberIdle` → `TurnEnded` → presence idle (the missing piece)
- parked forceWait member (`waitingForMessage=true`): `onMemberIdle` returns
  early, zero side effect
- forceWait CLI mid-`Stop` (not yet parked): `onMemberIdle` applies
  `TurnEnded`, which is correct — the turn has ended; the member is then
  re-parked via the `decision:block` reply. `reportsIdleViaReceiveWork=true`
  already skips the coordination-idle mail routing inside `onMemberIdle`, so
  no double delivery.
- so calling `notifyIdle` unconditionally for a non-empty member is safe

### 5. Data flow (normal path)

```
user submits → submitFullScreenInput → userTurnActive=true, seat=working
   ↓ cursor finishes, back at composer prompt
① cursor sends stop → /agent-status?event=stop → normalizer→done → seat cleared
② fallback: PTY fingerprint stable idleAfter → MemberTurnIdleSync endTurn
     → userTurnActive=false (simple)
     → onAfterTurnEnded → clearWorkingIfWorking (requiresPtyFallback)
③ mixed: cursor stop hook POST /idle → notifyIdle → bus.onMemberIdle
     → TurnEnded → claudeIsActive=false → presence idle
any first → workingSessionIds drops → "运行中…" disappears
```

### 6. Edge cases / error handling

- **waiting never cleared by fallback** — `clearWorkingIfWorking` reads state
  first; only `working → done`.
- **Cursor `stop` hook reliability** — investigated but does not block the
  fallback. Checkpoints: hooks.json lands in the fake HOME cursor reads; cursor
  may not emit `stop` in interactive composer mode (docs: fires when the agent
  loop ends); `hook_event_name` casing vs `'stop'`. If `stop` is reliable, the
  fallback still correctly no-ops; it stays enabled either way.
- **pending doorbell (mixed push)** — fallback skips when doorbell pending;
  `/idle` or `read_messages` ends the turn normally.
- **race / clock** — `clearWorkingIfWorking` is an idempotent read-check-write;
  done event + fallback colliding is a no-op.
- **30-min stale TTL** unchanged, as backstop.

## Testing

### Harness changes (root cause of "tests can't catch it")

- Bind `AgentAttentionCubit` in the simple idle/busy group too (currently only
  the mixed group binds it), so the attention-OR path is real in tests.
- New shell/attention helpers to simulate `/agent-status` hooks
  (`attention.applyEvent`) and drive done events / PTY-quiet fallback.
- New parameterized `turn_completion` harness keyed by `CliTool` × mode.

### Matrix: 5 CLIs × 2 modes × scenarios

Each (cli, mode):

| Scenario | Assertion |
|----------|-----------|
| A. submit → working | send/doorbell → `workingSessionIds` contains session |
| B. done event → clears | CLI's done event (Stop / session.idle / stop) → `workingSessionIds` empty |
| C. PTY-quiet fallback → clears (only requiresPtyFallback) | `simulateFingerprintQuietGap` → tick → empty; waiting seat NOT cleared |

Mode extras:

| Mode | Extra assertion |
|------|-----------------|
| simple | `historyTurnInFlight` → `liveChrome.none` (UI-level "运行中…" gone) |
| mixed | `/idle` POST → bus turn ends → presence idle; `notifyIdle` no-op for forceWait CLI |

Reachability:

- simple + cursor: scenario C is the regression test for this bug.
- simple + claude/codex/opencode: scenario B must pass; C is no-op.
- mixed + cursor: scenarios B and C (`/idle`→bus) both pass — covers the second
  root cause.
- every case asserts "PTY fallback does not clear waiting".

### Files

```
client/test/integration/turn_completion/
  turn_completion_harness.dart      # parameterized: open session, shell, attention, hook sim
  turn_completion_simple_test.dart  # 5 CLI × scenarios A/B/C (simple)
  turn_completion_mixed_test.dart   # 5 CLI × A/B + /idle assertions (mixed)
```

Reuses `RunningConnectedFakeShell`, `simulateFingerprintQuietGap`,
`postMemberIdle` from `session_idle_busy_harness.dart`.

## Implementation order

```
Phase 1 — capability layer
  1. TurnCompletionCapability + 5 CLI declarations
  2. AgentAttentionCubit.clearWorkingIfWorking()
  3. unit tests: capability/normalizer/clearWorkingIfWorking (waiting safe)

Phase 2 — fallback chain
  4. onAfterTurnEnded threaded (idle-watch → runtime → ChatCubit)
  5. ChatCubit._onTurnEnded: requiresPtyFallback + doorbell guard → clear
  6. integration test: simple + cursor scenario C (red first → green)

Phase 3 — /idle→bus
  7. handleIdleRequest → notifyIdle
  8. integration test: mixed + cursor /idle→bus; forceWait CLI no-op

Phase 4 — matrix
  9. turn_completion harness + simple group binds attention
  10. full 5 CLI × 2 mode matrix
  11. investigate cursor stop hook simple delivery; record findings

Phase 5 — full verification
  12. flutter analyze --no-fatal-infos --no-fatal-warnings
  13. flutter test (unit + integration)
```

## Verification strategy

- Regression test written first (simple + cursor scenario C), red → green.
- "waiting not cleared by fallback" asserted in every CLI case.
- simple cases assert `liveChrome.none` (UI-level), not just internal state.
- Each phase runs its own test set before moving on.
