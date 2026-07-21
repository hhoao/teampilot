# History mixed mailbox continue: design

## Problem

History continue always injects at the member PTY (`directToPty: true`). In
**mixed** TeamBus sessions, members that are in-turn or parked on
`wait_for_message` do not read operator stdin — they consume **mailbox** mail
(`TeamBus.deliverUserCommand` / `from: user`). History compose therefore looks
like it sends, but the agent never sees the line.

CLI transcripts never record mailbox user mail, so History optimistic thread
bubbles cannot reconcile via soft-reload text match.

## Goal

- Route History continue by seat/bus state: **PTY** when the member is idle at
  the TUI prompt; **mailbox** when TeamBus is installed and the member is
  waiting or in-turn.
- Surface mailbox deliveries in a compose-adjacent **Queued** strip while
  unread; after the member consumes the mail, promote to a **sticky user
  bubble** after the transcript tip (survives softReload; not in CLI
  transcript).

## Non-goals

- Landing compose routing
- Edit / reorder / retract already-delivered inbox mail
- Projecting the full TeamBus mailbox into the History thread
- Changing Terminal `ParkedSendOverlay` behavior

## Routing

```
resolveHistoryContinueChannel(
  teamBusInstalled,
  memberWaitingForMessage,
  memberInTurn,
) → pty | mailbox
```

| Bus installed | waiting | inTurn | Channel |
|---------------|---------|--------|---------|
| false         | *       | *      | pty     |
| true          | true    | *      | mailbox |
| true          | *       | true   | mailbox |
| true          | false   | false  | pty     |

**Mailbox path** must not call `ensureMemberInputReady(directToPty: false)` —
that waits for `wait_for_message` and blocks forever while the member is still
mid-turn. Connect (so the tab/bus exists), then `deliverUserCommand` with
`directToPty: false`, return the mail id.

**PTY path** keeps today’s ready-wait + stdin inject + first-prompt title.

## UX

Placement in `SessionHistoryReview`:

```
[ thread  — tip + sticky consumed mailbox bubbles + Running? ]
[ permission banner? ]
[ N Queued — unread mailbox mails | dismiss ]
[ compose card ]
```

Lifecycle:

1. Mailbox deliver success → Queued strip row `{mailId, text}`; skip
   optimistic thread pending when pre-submit peek is mailbox (confirmed again
   after connect).
2. While `isUnread(mailId)` → stay in Queued (poll ~1s; prune also runs on add).
3. When consumed (`!isUnread`) → remove from Queued and
   `AiHistoryCubit.appendStickyLocalUser(id: mailbox:{mailId}, text)` —
   FIFO after the committed tip; survives softReload; **does not** latch
   Running / awaitingAssistant. Promote only if the seat key still matches
   the seat that queued the mail.
4. Manual dismiss → hide Queued row only (no sticky bubble; mail stays in inbox).
5. Seat / session change → bump Queued `clearToken` (drop rows without
   consume) + `clearPendings` (stickies).
6. PTY success → existing thread pending + Running / live refresh.
7. Mailbox success does **not** start transcript live refresh.

Ordering: `visible transcript tip` → sticky mailbox users (FIFO) →
optimistic PTY pendings → Running placeholder (thread chrome).

**Declared `mailQueued` members** (activity without `wait_for_message`) still
use the waiting/inTurn table above — History continue does not special-case
them; extend routing later if needed.

## Failure

Connect / deliver failure → restore compose text; no Queued row; PTY path also
rolls back thread pending as today.
