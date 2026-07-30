# Concurrent `wait_for_message` mail-steal fix

## Problem

In mixed mode, a member can have two overlapping `wait_for_message` parks (new wait issued before the prior SSE disconnect is detected ~20s). Delivery wakes all waiters; the stale stream can `take` + `confirm` (mailbox shows read) while the live wait re-parks empty and the CLI never sees the tool result.

## Goals

- Live (newest) wait receives mail; stale wait cannot consume or mark read.
- New wait for the same member immediately cancels the prior wait stream.
- Do not reintroduce mutual park-completion spin / unbounded waiter growth.
- Stale `WaitExited` must not clear park while a newer wait is still active.

## Design (approach C)

### A — Newest-only wake/take (`MemberInbox`)

- Keep a waiter list (do not complete older waiters on new park).
- On deliver / restore: wake **only the newest** waiter.
- Older waiters stay parked until their cancel/timeout; then return empty without taking.
- `dispose` still wakes all.

### B — Per-member wait supersede (`WaitCancelRegistry`)

- Track in-flight wait cancel token by `memberId`.
- On register of a new wait for that member: cancel the previous token with `WaitCancelReason.superseded`.
- HTTP SSE and raw-socket wait paths both register with `memberId`.
- Before `confirm`, re-check cancel; if superseded/disconnected, `abort()` (redeliver) instead of marking read.

### Presence

- On `WaitExited`, if `cancelReason == superseded`, **skip** applying the exit (leave `turnDoneBusWait`). The newer wait’s `WaitEntered` already owns park; applying the stale exit would drop presence to `turnDoneReady` and wrongly re-enable doorbells.

## Non-goals

- Stronger than flush/write delivery proof to the CLI.
- Changing Cursor doorbell / `read_messages` push path.

## Follow-up (SSH raw-socket, 2026-07-30)

HTTP SSE fix above is necessary but not sufficient for remote members:

- Same `(token, memberId)` keeps at most one live raw-socket; newer handshake
  displaces the prior connection (tunnel flap / zombie relay).
- Supersede / disconnect writes a JSON-RPC error so the CLI tool call does not
  hang forever with no response.
- Socket disconnect cancels the in-flight wait token (park must not leak until
  the next mail wake).
- **Do not serialize MCP dispatch behind `wait_for_message`.** Local
  `teammate_bus_bridge` forwards concurrently; raw-socket must too. Otherwise
  Claude's overlapping `list_tasks` / `read_messages` / `notifications/cancelled`
  queue behind the park → every tool "times out" / "bus unavailable", and a
  timed-out wait can still `take`+`confirm` mail the CLI already abandoned.

## Tests

- Inbox: newest takes; older stays parked then empty on cancel; park still does not complete sibling.
- Registry: second register for same member cancels the first with `superseded`.
- HTTP: overlapping waits — mail confirmed only on the live stream; inbox not left stolen by the stale one.
- Raw-socket: displace on re-handshake; cancelled wait gets JSON-RPC error; disconnect clears park;
  short tools + cancel complete while wait is parked.
