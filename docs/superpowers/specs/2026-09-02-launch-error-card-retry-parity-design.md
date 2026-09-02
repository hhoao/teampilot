# Launch error card retry parity with user-bubble retry

Date: 2026-09-02  
Status: approved for planning

## Problem

When session launch fails, Chat shows a failure card above compose. Tapping **Retry** on that card calls `ChatCubit.retrySessionLaunch`, which reconnects first and only after settle may auto-redeliver the latest failed message.

Tapping **Retry** on a failed user bubble goes through `SessionChatView._retryFailedMessage` → `_deliverComposeMessage(retryRecord: …)`, which immediately marks the bubble pending, sets `awaitingAssistant`, and shows History **启动中** while connect/deliver runs via the normal `onSubmit` path.

Users experience the card retry as “nothing is starting” because Chat suppresses the full-screen session-starting overlay, and History live chrome only shows **启动中** when a turn is already in flight.

## Goal

In Chat, the launch-error card **Retry** must be behaviorally identical to the failed-bubble **Retry** whenever a failed outbound message exists.

## Non-goals

- Changing Terminal placeholder restore / remap-dead-SSH flows
- Showing full-screen session-starting overlay while workbench view is Chat
- Inventing a third progress surface beyond History live chrome + existing card `isRetrying`
- Changing bubble-retry semantics

## Behavior

1. Chat launch-error card **Retry** resolves the **latest** failed message for the active session (same selection rule used today by `_redeliverLatestFailedAfterLaunchRetry` / `latestFailedMessageRecord`).
2. If a failed record exists → invoke the **same** path as bubble retry: `_retryFailedMessage(id)` → `_deliverComposeMessage(retryRecord: …)` → pending + `awaitingAssistant` → History **启动中** → `onSubmit` (`submitSessionHistoryReviewMessage` connect + deliver).
3. If no failed record exists (pure launch failure) → keep calling `widget.onRetry` / `ChatCubit.retrySessionLaunch` (reconnect only; nothing to mirror).
4. Chat must **not** use the card path that reconnects first and then auto-redelivers. That post-connect redelivery is removed from the Chat card flow so a single deliver path owns feedback and injection.
5. Failure card may still show `isRetrying` while connect is in progress; success still clears via `finishSessionConnect`. Primary user-visible “we’re starting” signal is History live chrome, matching bubble retry.

## Wiring

### `SessionChatView`

Add a single entry used by compose / Chat failure-card `onRetry`, e.g. `retryLaunchOrLatestFailed()`:

1. Load failed records for the session.
2. If `latestFailedMessageRecord` is non-null → `_retryFailedMessage(record.id)`.
3. Else → `widget.onRetry?.call()` (existing `retrySessionLaunch`).

Bubble `onRetryFailedMessage` continues to call `_retryFailedMessage` directly (unchanged).

### `chat_workbench` / compose

- Chat surface: wire failure-card retry to the SessionChatView entry above (not a bare `retrySessionLaunch` when a failed bubble may exist).
- Terminal compact failure card / terminal placeholder restore: remain reconnect-only via `retrySessionLaunch` (no History bubble chrome).

### `ChatCubit.retrySessionLaunch`

- Keep for: no-failed-message Chat fallback, Terminal restore, other non-Chat callers.
- Stop Chat card from relying on `_redeliverLatestFailedAfterLaunchRetry` after connect. Prefer removing that auto-redelivery from `retrySessionLaunch` once Chat card uses bubble parity; if any non-Chat caller still needs silent redelivery, document it explicitly—default is **no** post-connect redelivery so Chat and bubble stay one path.

## Error / edge cases

| Case | Expected |
|------|----------|
| Latest failed exists | Card retry ≡ bubble retry for that id |
| No failed messages | Reconnect-only (`retrySessionLaunch`) |
| Retry while already submitting / same id in flight | Same guards as `_retryFailedMessage` |
| Connect fails again | Bubble returns to failed; launch error surface updates as today |
| Team member unresolved | Same as bubble/submit path (no separate card redelivery guess) |

## Testing

- With a failed bubble + launch error: card Retry shows pending + History starting tip; does **not** only reconnect then redeliver later.
- With launch error and **no** failed bubble: card Retry still reconnects.
- Bubble Retry behavior unchanged.
- Regression: Terminal launch-error compact Retry still reconnects without requiring a History turn.

## Out of scope follow-ups

- Morphing the red failure card into a neutral “starting” card when no failed bubble exists (reconnect-only feedback polish).
