# Session activity — Design

**Date:** 2026-08-30
**Status:** Approved (conversation); awaiting spec review

## Problem

Sidebar spinner, History “启动中/运行中”, terminal reclaim, and “Agent 已就绪”
all follow `workingSessionIds`, a single bool OR of:

- operator delivery (connect / composer wait / inject)
- turn latch (`userTurnActive` / TeamBus in-turn)
- agent-status attention (waiting / working)
- PTY idle-watch treating 2.5s unchanged screen as turn end

Those are different facts. First send walks through them in sequence, so
the spinner blinks and idle notify fires more than once. The delivery
in-flight flag fixed the send-gap spinner; it did not give consumers a
way to ask “can the user talk again?”

## Goals

1. One session-level activity snapshot with explicit **reasons**, not one bool.
2. Consumers pick a **view**: spinner vs ready-to-chat. No second parallel
   busy tracker.
3. Sidebar spinner stays on from operator send until the turn actually ends
   (or send fails / user Stop).
4. Idle notify fires **at most once per completed turn**, never on delivery
   wrap-end or PTY-quiet-while-thinking for CLIs that have Stop/done.
5. History Starting/Running and reclaim use the same snapshot.
6. Opening a stopped session without sending lights nothing.

## Non-goals

- Stretching `SessionPhase` through inject (full-screen Starting overlay).
- Latching `userTurnActive` at send time (`onConfirmedRunning` would clear it).
- Aborting `ensureMemberInputReady` on Stop (separate race).
- OS notification placement / desktop daemon settings.
- A 4s debounce on notify (rejected: papers over false idle).

No backward compatibility: `ChatState.workingSessionIds` and
`turnWorkingSessionIds` go away.

## Design

### 1. `SessionActivity`

New types under `client/lib/models/session_activity.dart` (immutable,
Equatable):

```dart
enum SessionBusyReason { delivering, inTurn, attention }

enum SessionTurnDisposition {
  none,
  completed, // agent finished the turn
  cancelled, // user Stop
  failed,    // send failed before a turn latched
}

class SessionActivity {
  const SessionActivity({
    this.reasons = const {},
    this.hadTurn = false,
    this.disposition = SessionTurnDisposition.none,
  });

  final Set<SessionBusyReason> reasons;
  final bool hadTurn;
  final SessionTurnDisposition disposition;

  bool get isBusy => reasons.isNotEmpty;
  bool get isDelivering => reasons.contains(SessionBusyReason.delivering);
  bool get isInTurn => reasons.contains(SessionBusyReason.inTurn);
  bool get isAttention => reasons.contains(SessionBusyReason.attention);

  /// Notify only: a completed turn just became idle.
  bool get isReadyToChat =>
      !isBusy &&
      hadTurn &&
      disposition == SessionTurnDisposition.completed;
}
```

`ChatState.sessionActivities` is `Map<String, SessionActivity>` (session id →
snapshot). Missing key = idle, no turn.

Derived convenience on cubit/state (not a second source of truth):

```dart
Set<String> get busySessionIds => {
  for (final e in sessionActivities.entries)
    if (e.value.isBusy) e.key,
};
```

Sidebar today is `workingFromState || pod.phase.isLaunching`. Keep
`isLaunching` on the pod; spinner = `activity.isBusy || isLaunching`.

### 2. Who writes reasons

| Reason | On | Off |
|--------|----|-----|
| `delivering` | `withOperatorDeliveryInFlight` begin | wrap `finally`, Stop `clear`, empty submit never begins |
| `inTurn` | `latchTurnStarted` (inject / UserLine / bus markTurn) | turn-end policy (below) or user Stop |
| `attention` | `sessionIsAgentActive` (waiting or working, mixed parked members excluded as today) | attention not active |

Aggregator (`SessionActivityAggregator`, replaces `TabWorkingAggregator`)
builds the map each recompute. It does not invent extra ORs.

`hadTurn` becomes true the first time `inTurn` or `attention` is on this
cycle. It stays true until the snapshot is reset after a disposition is
consumed (notify) or the tab closes.

`disposition`:

| Event | Disposition |
|-------|------------|
| Reasons empty after `inTurn`/`attention` ended by policy / done hook | `completed` |
| Compose Stop (clears delivering + inTurn; attention waiting may remain) | `cancelled` if we also clear attention-waiting for that seat’s Stop path; if permission waiting remains, stay busy with `attention` only — no notify |
| Delivery ends with no `hadTurn` | `failed` (no notify) |

Notify listener watches `sessionActivities`: session enters `isReadyToChat`
→ one `notifySessionsBecameIdle` call → cubit resets that session’s
`hadTurn`/`disposition` to `none` so it cannot fire again until a new turn.

Skip OS+center when focused and viewing that session (existing).

### 3. Turn-end policy

PTY quiet (`MemberTurnIdleSync` / `isQuietAfterTurnPtyActivity`) is a
**proposal**, not “ready to chat”.

```dart
bool ptyQuietEndsTurn(CliTool cli) =>
    registry.capability<TeamBehaviorCapability>(cli)?.requiresPtyFallback ?? false;
```

| CLI | `requiresPtyFallback` | PTY quiet |
|-----|------------------------|-----------|
| Claude, Codex, OpenCode, flashskyai | false | **do not** `endTurn` |
| Cursor | true | `endTurn` (only reliable signal) |

When PTY quiet does not end the turn, `inTurn` stays until:

- Agent-status **done** (`doneEventNames` / `AgentSeatAttention.done`) →
  `endTurn` for that seat (wire in `ChatCubit` / attention apply path).
- Compose Stop → `endTurn` + `endOperatorDeliveryInFlight` + disposition
  `cancelled`.

`onConfirmedRunning` still clears a stale latch at process start (must not
count as turn end for notify: no `hadTurn` yet, or delivering still on).

Mixed TeamBus: `onMemberIdle(..., fromPtyQuietWatch: true)` only if
`ptyQuietEndsTurn` for that member’s CLI. Otherwise bus turn stays until
done/Stop.

### 4. Consumers

| Consumer | View |
|----------|------|
| Sidebar tile / session list | `isBusy \|\| isLaunching` |
| Reclaim watch | `isBusy` (do not reclaim) |
| Idle notify | rising edge of `isReadyToChat` |
| History live chrome | `delivering` (and connecting / PTY not up) → Starting; `inTurn` or `attention` → Running; not busy → none. Compose Stop still wins (`cancelled` / not in flight). |
| Follow-up drain | `isBusy` for “member working” |

Replace `workingSessionIds.contains` call sites. Delete
`SessionIdleNotifyGate` quiet-period leftovers; gate becomes “fire when
`isReadyToChat` becomes true”.

`OperatorDeliveryInFlight` stays as the writer of `delivering`.

### 5. Data flow (first send, Claude)

```text
send
  → delivering on          spinner on, no notify
  → connect / composer
  → inject → inTurn on     delivering off in finally; spinner still on
  → TUI static 2.5s       idle-watch does NOT endTurn
  → Stop/done hook         inTurn off, attention off
  → reasons empty, hadTurn, completed
  → one “Agent 已就绪” (unless focused on this session)
```

Cursor: same until after inject; 2.5s quiet **does** endTurn → one ready
notify (may still be early if the model is thinking with a static TUI; no
better signal exists).

### 6. Failure and Stop

| Event | Activity | Notify |
|--------|----------|--------|
| Empty submit | never `delivering` | no |
| Connect / ready / inject fail | `delivering` off, `failed` | no |
| Stop during composer wait | `delivering` clear, `cancelled` | no |
| Stop during inTurn | `inTurn` off, `cancelled` | no |
| Open, no send | empty | no |

## Testing

Unit, no live CLI:

1. Aggregator: delivering-only → busy, not `isReadyToChat`; latch + drop
   delivering → still busy; completed empty reasons + `hadTurn` →
   `isReadyToChat`.
2. Turn-end policy: `requiresPtyFallback` false → quiet does not call
   `endTurn`; true → does.
3. Notify: delivery falling edge does not notify; completed turn notifies
   once; Stop/fail does not; focused active tab still skipped.
4. ChatCubit: wrap lights `delivering`; Stop clears it while wrap outstanding.
5. History chrome resolve: delivering + not member running → starting;
   inTurn → running.

Keep existing delivery-in-flight wrap tests, pointed at `SessionActivity`.

## Out of scope later

- Abort composer wait on Stop so inject cannot land after cancel.
- A thinking-timeout for Cursor if PTY quiet is too aggressive.
