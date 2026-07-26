# Virgin lead idle-announce doorbell

## Problem

In mixed TeamBus, a member at-prompt who has never entered a turn
(`hasEverBeenActive == false`) does not get a PTY doorbell when every unread
message is an `idle_notification`. Worker park idle therefore queues mail on a
virgin lead without ringing, so the lead stays silent until the operator starts
History compose.

That suppression was intentional (compose owns the first turn), but it stalls
collab when workers report idle before the lead has typed anything.

## Goal

Treat idle-announce like ordinary teammate mail for doorbell decisions: if the
member is running at-prompt with unread mail, ring — including virgin seats and
idle-only inboxes.

## Design

Remove the virgin-lead special case entirely (approach 1).

### Behavior

`PresenceReducer` `MailArrived` on at-prompt with unread and not already
doorbelled → emit `DoorbellEffect` (existing path). No exception for
`!hasEverBeenActive && unreadIsIdleOnly`.

Unchanged:

- Mid-turn (`active`): no doorbell
- Parked (`wait_for_message`): no doorbell (waiter delivers)
- Already `doorbelled` this unread round: no re-ring (watchdog still reengages)

### Code cleanup

Delete fields/helpers that exist only for the virgin rule:

- `PresenceContext.hasEverBeenActive`, `PresenceContext.unreadIsIdleOnly`
- `AgentNode.hasEverBeenActive` (constructor init + `TurnStarted` setter in
  `TeamBus._reduce`)
- `TeamBus._unreadIsIdleOnly`

### Tests / harness

- Flip unit expectations: virgin at-prompt + idle-only → doorbell
- Update `team_bus_idle_doorbell_test` / `idle_notification_test` / reducer tests
- CLI matrix `parkWorkerAndComposeOnLead`: stop relying on “idle queues without
  doorbell”; after worker park the lead may receive a doorbell and start a turn.
  Adjust harness/comments so History compose still works (compose after park, or
  tolerate lead already doorbelled)

## Non-goals

- Changing doorbell notice text
- Changing `LeaderStarCoordinationPolicy` who sends idle announces
- Configurable restore of the old “compose-first” rule
