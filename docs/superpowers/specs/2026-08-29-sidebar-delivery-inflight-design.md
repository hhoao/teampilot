# Sidebar delivery in-flight — Design

**Date:** 2026-08-29
**Status:** Approved

## Problem

Sending a message (Chat continue, landing first prompt, follow-up, automation)
runs `connect → ensureMemberInputReady → inject`. The sidebar spinner is:

```dart
workingFromState || pod.state.phase.isLaunching
```

`isLaunching` is true only while `SessionPhase` is provisioning/connecting.
`workingSessionIds` is true only after inject calls `latchTurnStarted()`
(`userTurnActive` / bus turn) or attention is busy.

Between `finishSessionConnect` (PTY confirmed, phase `running`) and inject,
the seat is waiting on boot frame + composer. The sidebar goes idle while the
user bubble is already on screen and History still shows Starting/Running.
That idle gap reads as **send failed**.

History already holds the footer via `awaitingAssistant` +
`historyContinueInFlight`. The sidebar does not.

## Goals

1. Sidebar spinner stays on from operator send start until either the turn
   latches or the send fails / the user Stop-cancels the wait.
2. Cover every path that does connect/wait/inject: Chat continue (including
   workbench, which currently calls `submitSessionHistoryReviewMessage`
   without going through `ChatCubit.submitSessionOperatorMessage`), landing
   first prompt, follow-up drain, automation dispatch.
3. Failed send and compose Stop still clear the spinner immediately. Opening a
   stopped session without sending must not light working.
4. After a successful inject, existing idle-watch / done / attention rules
   still end the turn. Do not pin busy forever.

## Non-goals

- Changing `SessionPhase` so connecting lasts until inject (would revive the
  full-screen Starting overlay and lie about phase).
- Latching `userTurnActive` at send time (conflicts with
  `onConfirmedRunning` clearing the latch; false-lights on open-without-send).
- Aborting `ensureMemberInputReady` on Stop (existing race: Stop clears
  History chrome while the submit future may still finish). This spec only
  aligns the **sidebar** with Stop.
- Changing History live chrome, `awaitingAssistant`, or
  `historyAwaitingIdleGrace`.
- Changing `MemberTurnIdleSync`, `MemberCoordination`, or the attention-OR
  meaning. Adding a third OR for delivery in-flight is in scope; rewriting
  the aggregator is not.

## Design

### 1. Session-level in-flight flag

`ChatCubit` owns `Set<String> _operatorDeliveryInFlightIds`.

```dart
Future<T> withOperatorDeliveryInFlight<T>(
  String sessionId,
  Future<T> Function() action,
) async {
  _beginOperatorDeliveryInFlight(sessionId);
  try {
    return await action();
  } finally {
    _endOperatorDeliveryInFlight(sessionId);
  }
}
```

Begin/end are refcounted per session so a nested wrap cannot clear too early.
Empty/whitespace no-op submits never begin. `end` at count 0 is a no-op
(Stop may zero the count while the wrap is still in `finally`).

`TabWorkingAggregator`:

```dart
if (sessionWorking || attentionBusy || deliveryInFlight) working.add(sessionId);
```

Wire `sessionBusyFromDeliveryInFlight` next to `sessionBusyFromAttention` on
the aggregator (and pass the same callback into `TabMemberReclaimWatch.inTurn`
so a 10-minute composer wait cannot be reclaimed at the 180s idle threshold).

Begin/end call `_recomputeWorkingSessions()` so the sidebar updates without
waiting for the next idle-watch tick.

### 2. Call sites (must wrap connect/wait/inject as one unit)

| Path | Wrap |
|------|------|
| `ChatCubit.submitSessionOperatorMessage` | whole `submitSessionHistoryReviewMessage` |
| `chat_workbench.dart` History `onSubmit` | same helper around its direct submit call |
| Landing `submitWorkspaceLandingMessage` | `_ensureLandingSessionConnected` + `deliverUserCommandToMember` |
| Follow-up | already goes through `submitSessionOperatorMessage` |
| Automation | `_ensureSessionConnected` + `deliverUserCommandToMember`, via an injected `withOperatorDeliveryInFlight` (or wrap both on `TabTeamBusGateway`). Dispatcher must not import `ChatCubit`. |

Do **not** begin inside `ensureMemberInputReady` alone: that would miss the
tiny gap after ready returns and before inject, and would require every
orchestrator to remember a matching end.

`submitSessionHistoryReviewMessage` itself stays a pure orchestrator. Cubit
owns the flag so workbench/landing/automation can share one API.

Mailbox channel: the wrap still covers connect + mailbox deliver. After
success, finally clears in-flight; mailbox is not a PTY turn, so the sidebar
goes idle unless another signal is busy. That matches today after deliver
returns.

### 3. Failure and Stop

| Event | Sidebar |
|-------|---------|
| Connect / ready-wait / inject throws or returns failed | `finally` ends in-flight → idle (failed bubble / toast unchanged) |
| Empty message no-op | never begins |
| Compose Stop during Starting | view calls `ChatCubit.endOperatorDeliveryInFlight(sessionId)` (zero the count) so sidebar matches History clearing awaiting |
| Inject then succeeds after Stop | `latchTurnStarted` lights working again — real turn started; not a false send |
| Open session, no send | never begins |

Success path: inject latches the turn **before** the wrap's `finally`. Ending
in-flight does not drop the spinner; `userTurnActive` / bus turn / attention
keep `workingSessionIds`.

### 4. Data flow

```text
operator send
  → withOperatorDeliveryInFlight(sessionId)
       → workingSessionIds includes session  (sidebar on)
       → connect (isLaunching may also be on)
       → finishSessionConnect (isLaunching off; in-flight still on)
       → ensureMemberInputReady (composer wait)
       → inject → latchTurnStarted
  → finally end in-flight
       → workingSessionIds still contains session via turn latch
```

## Testing

Unit, no PTY:

1. `TabWorkingAggregator`: delivery-in-flight alone puts the session in
   `compute()`; clearing it with no other busy signal removes it; OR with
   `sessionWorking` / attention still works.
2. `withOperatorDeliveryInFlight`: nested begin does not end until the outer
   finally; exception in `action` still ends; empty session id is a no-op.
3. `submitSessionHistoryReviewMessage` tests stay unchanged (pure function).
   ChatCubit / landing tests assert: after connect-finished and **before**
   inject callback, `workingSessionIds` contains the session; after failed
   ready-wait it does not.

Do not require a full integration CLI boot for the gap. Drive the wrap +
aggregator with fakes (same style as `chat_cubit_simple_working_test`).

## Out of scope later

If Stop should also abort composer wait (so inject cannot land after cancel),
that is a separate spec. This one only stops the sidebar from looking idle
mid-send.
