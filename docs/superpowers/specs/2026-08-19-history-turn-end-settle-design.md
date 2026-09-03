# History turn-end settle — Design

**Date:** 2026-08-19
**Status:** Layer 1 approved; Layer 2 **superseded** by
[2026-09-03-remove-history-turn-end-force-settle-design](2026-09-03-remove-history-turn-end-force-settle-design.md)

## Problem

When a Cursor (and any JSONL) turn ends, History can miss the last assistant
event. Two independent gaps compose:

1. **Parser** — `AiTranscriptTailReader._consumeFromAnchor` drops a trailing
   fragment that has no `\n`, waiting for a "next round" that never comes after
   the file stops growing. `_fullReload` and `LineSplitter` already accept a
   final line without newline. Incremental vs full output then diverges.
2. **Timing** — Cursor's per-turn `stop` hook is unreliable
   (`requiresPtyFallback`). PTY-quiet (~2.5s) clears `workingSessionIds` and
   History `awaitingAssistant` without reloading transcript. Cursor often
   appends the final prose JSONL line *after* the TUI is quiet. Live refresh
   may already have run on the pre-flush file; token cache / 1s throttle can
   skip the next pass.

Cursor writes many tool-only `assistant` lines during the turn and the
user-visible closing text as a later JSONL line (coalesced into one bubble).
Missing that line looks like "the last message never refreshed."

## Goals

1. Incremental JSONL parse at EOF matches full parse for a complete JSON
   object with no trailing newline. Incomplete JSON stays deferred.
2. When a History turn leaves awaiting (PTY quiet / done / idle grace), the
   seat force-reloads from disk without wiping live-refresh tail state via
   `invalidate`, and without CLI `if (cli == cursor)` branches.
3. New JSONL CLIs inherit both behaviors.

## Non-goals

- No new `AiHistoryCapability` / `TeamBehaviorCapability` flags.
- Do not call `AiHistoryCubit.softReloadIfSession` on turn end (it
  `invalidate`s and full-reparses).
- Do not change adjacent-assistant coalescing.
- Do not special-case Cursor in `ChatCubit._onTurnEnded`.

## Design

### Layer 1 — JSONL tailer (shared)

In `_consumeFromAnchor`, newline-split as today. The bytes after the last
`\n` are the file suffix (windows are always file suffixes ending at EOF).

- Decode that remainder with the same event decoder.
- **Valid object** → consume like a complete line; advance `anchorHash` to
  the remainder's line hash. A later `\n` with no extra bytes is a no-op
  (same hash).
- **Invalid / incomplete** → ignore remainder this round (existing
  half-written test).

No CLI dialect here; `lineAppend` still decides which events become messages
(`turn_ended` stays noise).

### Layer 2 — Seat settle (shared)

**Superseded 2026-09-03 — seat force settle removed.**

`AiHistorySeat` owns awaiting. `flushHeldTip(endAwaiting: true)` is the
single turn-end commit (working falling edge and idle-grace both call it).

On that path:

1. Immediate `softReload(force: true)` — skips the loader mtime/token cache
   and forces the tailer `_fullReload` / incremental `force` branch so an
   already-read last line is re-consumed.
2. One delayed `softReload(force: true)` after
   `historyTurnEndSettleDelay` (800ms) to catch a flush that lands after
   quiet. Cancel if the seat closes or a new user turn starts
   (`enqueuePendingUser`).

Live watch stays as-is (route-active History keeps `AiHistoryLiveRefreshController`).
Settle does not `invalidate` the loader.

`softReload({bool force = false})` is the only new seat API; default
preserves today's live-refresh path.

## Testing

- Tailer: complete JSON at EOF without `\n` is consumed; half-written still
  deferred; appending `\n` after a consumed remainder does not duplicate.
- Seat (Layer 2 superseded): see
  [2026-09-03-remove-history-turn-end-force-settle-design](2026-09-03-remove-history-turn-end-force-settle-design.md).
  `ai_history_seat_no_turn_end_force_reload_test.dart` asserts turn-end chrome
  does not force-reload under a frozen token; late flush is owned by live watch
  (`ai_history_live_refresh_controller_test.dart`).

## Rollout

Parser first (correctness), then seat settle (timing). No capability
registry changes.
