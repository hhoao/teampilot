# Remove History turn-end force settle — Design

**Date:** 2026-09-03  
**Status:** Approved  
**Supersedes:** Layer 2 of [2026-08-19-history-turn-end-settle-design](2026-08-19-history-turn-end-settle-design.md)  
**Keeps:** Layer 1 (EOF complete JSON without `\n`) from that same design

## Problem

On Cursor (and other PTY-quiet) turn end, History `flushHeldTip(endAwaiting: true)` schedules:

1. Immediate `softReload(force: true)`
2. Another `softReload(force: true)` after `historyTurnEndSettleDelay` (800ms)

That path was added because Cursor often appends the final assistant JSONL line
**after** PTY quiet, and a frozen mtime token / live throttle could miss it.

It is the wrong layer for timing:

- Warm seats already keep `AiHistoryLiveRefreshController` while History is
  route-active (`isHistorySeatHot`: `routeActive || isMemberRunning`).
- `force: true` does **not** mean full JSONL reparse (post-warm incremental
  stays), but it **does** skip the mtime token short-circuit and **bypass
  in-flight load coalescing**, so turn-end can start a parallel incremental
  load on the same edge as idle-notify and tip reveal.
- The delayed settle is a fixed timer — defensive timing, not a signal.

Symptom: Chat hitches ~1s when the session becomes idle / idle notification
fires. The settle is correlated; the notification is not the root.

## Goals

1. Remove seat turn-end force settle entirely (immediate + delayed).
2. Late transcript flush is picked up only by live change signal →
   `softReload(force: false)` (warm incremental; mtime/token short-circuit
   when unchanged).
3. Keep Layer 1 EOF tailer behavior; keep `softReload({force})` API for
   explicit callers that still need token bypass (manual refresh), but
   **do not** call it from `flushHeldTip`.
4. No new CLI special-cases; no coalesce / “if live running skip” guards
   around settle (settle is deleted, not gated).

## Non-goals

- Changing idle-notification placement or OS notify.
- Last-bubble markdown relayout (separate slice).
- Reopening full-parse-on-hot-path; warm incremental-only stays.
- Replacing settle with another fixed delay or post-frame deferral.
- Calling `softReloadIfSession` / `invalidate` on turn end.

## Design

### 1. Delete Layer 2 from the seat

In `AiHistorySeat`:

- Remove `_turnEndSettleTimer`, `_scheduleTurnEndSettle`,
  `_cancelTurnEndSettle`.
- `flushHeldTip(endAwaiting: true)` only commits tip / clears
  `awaitingAssistant` — **no** softReload.
- Drop `historyTurnEndSettleDelay` if nothing else references it.
- Cancel hooks on `enqueuePendingUser` / `close` that only existed for
  settle go away with the timer.

Update [2026-08-19](2026-08-19-history-turn-end-settle-design.md): mark Layer 2
**superseded**; Layer 1 remains approved.

Update `docs/cli-formats/cursor.md` “回合结束的最后一行” bullet: EOF tailer
stays; remove the force-settle sentence; point at this doc.

### 2. Late flush ownership = live watch only

While History is hot, `TranscriptChangeSignal` / poll already drives
`AiHistoryLiveRefreshController` → `softReload()` (default `force: false`).

Contract after this change:

| Event | History update path |
|-------|---------------------|
| File grows / token moves while hot | Live refresh softReload |
| Turn leaves awaiting (PTY quiet / done / idle grace) | Chrome only (`flushHeldTip`); no reload |
| Cold → hot remount | Existing softReloadOrLoad / ensureStarted |
| Compact / truncate / invalidate | Existing cold / Invalidated paths |

If a late Cursor flush lands **after** quiet while the user is on History,
the watch must fire. If it does not, that is a **watch/token bug** to fix
at the signal or cache-token layer — not a reason to resurrect seat settle.

### 3. Tests

**Remove / rewrite** `client/test/cubits/ai_history_seat_turn_end_settle_test.dart`:

- Delete tests that assert `flushHeldTip` / working falling edge force-reveals
  under a frozen token, and delayed settle / cancel-on-enqueue.
- Those tests encoded the defensive Layer 2 contract and must not be
  “fixed” by reintroducing settle.

**Add** a live-refresh regression (unit or thin controller test):

- Warm seat + active live refresh (or a fake `TranscriptChangeSignal`).
- Initial transcript without final prose; frozen or advancing token as
  appropriate for the signal under test.
- Append final assistant line on disk (or fixture map + bump token /
  fire `onChanged`).
- Assert `softReload(force: false)` path (or controller `refreshNow` /
  change callback) reveals `final-*` **without** calling
  `flushHeldTip` / without seat settle timers.

Keep existing tailer EOF tests (Layer 1) unchanged.

### 4. Manual check

Cursor simple session, History visible: send a turn that ends with a
late-written closing line. After idle chrome clears, final text must
appear from live refresh alone. No forced settle in logs
(`[ai-history]` softReload from turn-end path gone).

## Risks

| Risk | Mitigation |
|------|------------|
| Late flush missed when History is **cold** (not route-active, member not running) | Unchanged: cold seats do not live-refresh today; remount / softReloadOrLoad still hydrates. Out of scope. |
| Watch misses an append that does not move cache token | Fix token / signal (e.g. size+mtime), do not restore settle. |
| Idle-notify jank remains after settle removal | Profile; next suspect is tip reveal / markdown, not re-add settle. |

## Rollout

1. Spec review (this file).
2. Plan → delete settle + rewrite tests (TDD: failing live-watch late-flush
   test first if replacing settle coverage).
3. Update 2026-08-19 status note + cursor.md.
4. No capability registry changes.
