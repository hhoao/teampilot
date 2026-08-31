# Pending user bubble dedupe on session switch

**Date:** 2026-08-31  
**Status:** Implemented  
**Related:** [failed-message-history](2026-08-27-failed-message-history-design.md), optimistic pending reconcile in `AiHistorySeat`

## Problem

Sending a History continue message persists an optimistic user bubble
(`persistPendingUser` / `sending` on disk) and appends it as a **pending
overlay** at the tip of the thread. The overlay is intentionally kept until
transcript softReload confirms a new applied tip (`_reconcilePendings`),
because the CLI may rewrite the typed text (slash-command expansion).

Switching to another session and back can leave **two identical user bubbles**:
one from the CLI transcript (normal position) and one pending overlay stuck at
the bottom. Root causes:

1. **Cold → hot skips softReload.** Returning to a keep-alive session starts
   live refresh with `skipInitialRefresh: true`, so writes that landed while
   the seat was cold are never applied / reconciled.
2. **Hydrate after first-apply baseline.** `_loadHistoryThenHydratePersistedPendingUsers`
   loads the transcript (first apply only baselines, does not drop pendings),
   then restores stale `sending` as `failed` overlay on top of an already
   confirmed user turn — a second bubble by design of the current hydrate path.
3. **fullIndex / loadOlder advance the baseline without reconcile.** They call
   `_rememberAppliedSnapshot` so a later softReload can treat the tip as
   unchanged and early-return, leaving the overlay forever.

Product choice: if the transcript already reflects the send, **silently treat
delivery as success** — drop memory + disk pending; never show a duplicate
failed bubble for that case.

## Goals

1. At most one UI bubble per successful user send (transcript owns it once
   confirmed).
2. Single confirmation rule owned by `AiHistorySeat`; hydrate and foreground
   refresh obey it.
3. Real delivery failures still restore as retryable `failed` when the
   transcript does **not** confirm the send.
4. No measurable cost for idle session tab switches (no unconditional softReload).

## Non-goals

- Reintroducing text-matched pending reconcile (slash rewrite remains a reason
  not to compare pending text to transcript text).
- Changing mailbox Queued strip / TeamBus parked overlay behavior.
- Marking records `sent` on disk as a long-lived status (removal on confirm is
  enough; `FailedMessageStatus.sent` may remain unused).
- Changing sidebar delivery-in-flight / `awaitingAssistant` chrome beyond what
  pending drop already does today.

## Design

### 1. Invariant

```text
optimistic pending overlay ⊆ "transcript has not yet confirmed this send"
```

CLI / merged applied timeline is ground truth. Pending is only an overlay
until confirmation; then memory queue and persisted record are both removed.

Confirmation stays **tip / id-sequence based** (existing `_reconcilePendings`):
do not compare pending text. First apply of a cold load still baselines without
dropping in-flight seed/pending that must survive that load; hydrate then
decides whether restored disk records are still unconfirmed.

### 2. Hydrate: confirm-or-restore

After history load (when `_appliedSnapshotSeen` and `_allMessages` are the
post-load snapshot), `hydratePendingUsers` must not treat “any prior history
tip” as confirmation — that would delete a **new** failed send sitting on top
of an older conversation.

| Disk record | Confirmed by transcript (below) | Action |
|-------------|------------------|--------|
| `sending` | yes | **Remove from store**; do not enqueue (silent success) |
| `sending` | no | Persist as `failed`, enqueue overlay (today’s stale-sending path) |
| `failed` | yes | **Remove from store**; do not enqueue |
| `failed` | no | Enqueue failed overlay (unchanged) |
| `sent` | — | Skip (unchanged) |

**“Confirmed by transcript” for hydrate** — either signal is enough (no sole
reliance on tip emptiness):

1. **Time:** any loaded **user** message with a non-null `createdAt` that is
   `>= record.createdAt` (allow a small clock skew, e.g. 2s), or
2. **Text:** any loaded user message whose normalized plain text equals
   `normalizeAiHistoryPendingText(record.text)` (covers missing CLI
   timestamps; slash-expanded success still needs (1) or in-session tip
   reconcile).

Empty / pending-only seats confirm nothing — records stay on the failed
recovery path.

In-session softReload confirmation remains tip/id-sequence only (no text), so
slash rewrite while the seat is alive is unchanged. Hydrate’s text arm is only
a reopen fallback when timestamps are missing.

Do not enqueue a record whose id is already in `_pendingQueue` (unchanged).

Call sites stay `_loadHistoryThenHydratePersistedPendingUsers` — hydrate still
runs **after** load so the snapshot used for confirm is the CLI baseline, not
an empty pre-load seat.

### 3. Foreground: conditional softReload

When a History seat transitions **cold → hot**
(`isHistorySeatHot` becomes true via `routeActive` and/or `isMemberRunning`):

```text
if (seat.hasOptimisticPending || seat.state.awaitingAssistant)
  start / ensureStarted with skipInitialRefresh: false
  // i.e. refreshNow / softReload once, then attach watch
else
  skipInitialRefresh: true   // today’s cheap path
```

Idle tab switches pay nothing. The repro path (send → switch away → CLI
writes → switch back with leftover pending or still-awaiting) pays one
softReload; unchanged mtime/token cache keeps that cheap when there is nothing
new.

Wire this in `SessionChatView` (`didUpdateWidget` routeActive, and the
busy/running `BlocListener` path that calls `_maybeStartLiveRefreshForRunningPty`)
so offstage seats that become hot because the member started running also
refresh when pending/awaiting is set — not only when the tab is selected.

### 4. fullIndex / loadOlder must reconcile

Replace “`_remergePendingsOntoRuntime` + `_rememberAppliedSnapshot` only” with
the same tip-change path used by softReload:

- Apply the longer / prepended timeline into `_allMessages`.
- Call `_reconcilePendings()` (or equivalent: if snapshot already seen and tip
  / id sequence changed → `_dropAllPendings(removePersisted: true)`, then
  update `_lastApplied*`).
- Then remesh runtime / emit ready.

Prepends that keep the same tip must not clear pendings (existing intent of
`_rememberAppliedSnapshot` for loadOlder). Tip change (including a user turn
that landed during fullIndex) must clear them.

### 5. Performance

| Path | Cost |
|------|------|
| Idle session switch | Unchanged (`skipInitialRefresh`) |
| Switch back with pending/awaiting | One softReload; cache hit ≈ no-op |
| Hydrate confirm check | O(records); bind-time only |
| fullIndex reconcile | Id/tip compare; drop only if pending exists |

No new polls, no unconditional per-tab softReload.

## State flow (success + switch)

```text
compose submit
  -> persist sending + overlay
  -> deliver / inject
  -> user switches session (live refresh may stop if cold)
  -> CLI writes user turn
  -> user switches back (hot)
       -> hasOptimisticPending || awaitingAssistant
       -> softReload
       -> tip changed -> drop pending + remove disk record
       -> single transcript user bubble
```

```text
reopen / remount after successful send already in transcript
  -> load (baseline)
  -> hydrate: time or text confirms -> remove sending/failed record, no overlay
  -> single transcript user bubble
```

```text
reopen after true delivery failure (empty transcript, or history tip older
than record / text unmatched)
  -> load
  -> hydrate: no confirm -> failed overlay + Retry
```

## Testing

1. **Seat hydrate success:** load transcript whose user turn matches record
   text (or `createdAt >= record.createdAt`) + disk `sending` → no
   `pending:*` overlay; store empty for that id.
2. **Seat hydrate keeps real failure on prior history:** load older user/assistant
   turns + disk `sending`/`failed` for a *newer* unmatched text → failed
   overlay retained (must not wipe just because history is non-empty).
3. **Seat hydrate empty:** empty load + disk `sending` → failed overlay
   (existing behavior).
4. **fullIndex:** pending overlay + fullIndex that adds a new tip → pending
   dropped and persisted removed.
5. **Foreground gate (unit or view-level):** cold→hot with
   `hasOptimisticPending` requests softReload / `skipInitialRefresh: false`;
   without pending/awaiting keeps skip.
6. **Regression:** command-expanded user turn still clears typed pending
   (existing softReload test).

## Implementation touchpoints

- `client/lib/cubits/ai_history_seat.dart` — hydrate confirm-or-restore;
  fullIndex / loadOlder reconcile
- `client/lib/pages/chat/session_chat_view.dart` — conditional
  `skipInitialRefresh` on cold→hot
- Tests under `client/test/cubits/ai_history_seat_*.dart`,
  `client/test/pages/chat/session_chat_view_failed_message_test.dart`, and/or
  live-refresh / seat-hot helpers

## Out of scope follow-ups

- Explicit `sent` finalization write before remove (optional bookkeeping).
- FIFO multi-pending queue (seat already keeps a single overlay).
