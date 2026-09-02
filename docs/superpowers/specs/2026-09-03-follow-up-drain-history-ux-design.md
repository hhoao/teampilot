# Follow-up drain History send UX parity

Date: 2026-09-03  
Status: approved for planning

## Problem

When a Follow-up queue item auto-drains, delivery goes through
`ChatCubit._deliverFollowUpAtSeat` → `submitSessionOperatorMessage` and never
through `SessionChatView._deliverComposeMessage`.

Manual History continue therefore shows:

- **PTY:** optimistic pending user bubble + awaiting / 启动中 tip, then live
  refresh until transcript reconcile
- **mailbox:** compose-adjacent Queued strip (no History pending bubble)

Follow-up drain shows neither, so Chat looks idle until a later transcript or
mailbox merge catches up.

## Goal

Follow-up drain uses the **same channel-aware History send UX** as manual
History continue.

## Non-goals

- Changing Follow-up enqueue / pause / resume / strip UI
- Putting optimistic UX inside bare `submitSessionOperatorMessage` (shared with
  Terminal and with compose `onSubmit`, which already does optimism in the view)
- Changing mailbox channel resolution rules
- Backward-compatible dual paths or feature flags

## Design

### Root cause

Drain bypasses the History continue optimism layer. Fix by giving drain that
layer explicitly, not by special-casing widgets.

### Operator History Send UX

Introduce a focused helper (name e.g. `runOperatorHistorySendUx` or a small
`OperatorHistorySendUx` type) used by Follow-up drain:

1. Resolve `HistoryContinueChannel` the same way as
   `submitSessionOperatorMessage` / workbench peek
   (`resolveHistoryContinueChannel` + TeamBus waiting / in-turn).
2. **PTY**
   - Before deliver: `persistHistoryPending` for the seat
   - Deliver via existing `submitSessionOperatorMessage`
   - Failure: `markHistoryPendingFailed`
   - Success: notify Chat to start History live refresh / soft-reload for that
     seat (reuse or add a narrow cubit → view hook; do not leave pending orphaned
     without refresh). Pending stays until transcript reconcile (same as compose).
3. **mailbox**
   - Do **not** create a History pending bubble
   - Deliver via `submitSessionOperatorMessage`
   - Success: emit a cubit-level mailbox-queued event
     `{sessionId, memberId, mailId, text}`; `SessionChatView` feeds the existing
     `_mailboxQueued` / `HistoryMailboxQueuedStrip` path and refreshes mailbox
     timeline for the seat (same as compose `onMailboxConsumed` / refresh).
   - Failure: no pending record to mark; surface failure only via existing drain
     logging / queue retention (`FollowUpQueueDrainer` already keeps the head on
     `!result.ok`).

### Wiring

| Caller | Behavior |
|--------|----------|
| `_deliverFollowUpAtSeat` | Always run through Operator History Send UX |
| `SessionChatView._deliverComposeMessage` | Unchanged (already owns optimism); subscribe to cubit mailbox-queued events for the active seat so drain-originated mails share the strip |
| `submitSessionOperatorMessage` | Remains the bare connect+deliver primitive |

### Error / edge cases

| Case | Expected |
|------|----------|
| No HistoryStore / seat yet | Persist APIs already no-op / return null — drain still delivers; no fake bubble |
| PTY deliver fails | Failed bubble + retry affordance like other failed pendings |
| Mailbox deliver fails | Head stays in Follow-up queue; no History pending |
| Seat switch mid-drain | Existing Queued strip clearToken / seat-key guards apply to cubit-fed events |

## Testing

- Unit: Operator History Send UX — PTY persist before deliver; fail marks failed;
  mailbox success emits queued event and does not persist History pending.
- Drainer / cubit: `_deliverFollowUpAtSeat` (or test double) shows pending seat
  message for PTY path.
- View (if cheap): cubit mailbox-queued event appears on Queued strip for active
  seat.

## Out of scope follow-ups

- Routing Terminal operator send through the same UX
- Unifying compose `_deliverComposeMessage` to call the same helper (possible
  later DRY; not required for this fix)
