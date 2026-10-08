# Incremental-only AI History Loading (Strict Mode)

Date: 2026-09-18
Status: Approved design (brainstorming complete)

## Problem

The session AI-history loader (`AiHistoryLoader`) keeps an **adapter full-parse
fallback** that silently rescues nearly every situation where the incremental
paths (JSONL tail-anchor reader, opencode SQLite row-level refresher) decline:

- locate/parse transient failure → full parse
- incremental refresher returns null (count fallback / deletion / compression /
  schema mismatch) → full parse
- tail anchor lost / head rewritten / non-JSONL storage → full parse
- page-first incomplete window → background `_scheduleFullIndex` full parse

Because failures always land in a working fallback, weaknesses in the
incremental parsers never surface. This is defensive programming that hides
bugs. The goal: **make incremental parsing the only way to load history**, and
when it cannot parse, **fail loudly** so developers see the gap and fix it.

## Non-goals

- Keep page-first first paint (unchanged).
- Keep the mtime/size cache token (unchanged).
- Keep all no-blank/transient guard rails — they protect real user UX and are
  distinct from the removable full-parse fallback.

## Decisions (from brainstorming)

1. **Strict incremental-only.** Remove the adapter full-parse branch from the
   loader entirely. Each CLI's incremental machinery must cold-seed itself.
2. **Error loudly on decline.** Deletion becomes a *handled* incremental case.
   Count fallback / schema mismatch / anchor loss / head rewrite throw a typed
   error.
3. **Transient failures keep prior content + visible error** (no blanking).

## Architecture

New canonical `_loadOnce` shape:

```
token cache hit → return cache
page-first (first paint) → warm-incremental seed (background) → return
incremental refresh (tail / DB row-level) → merge in place → return
  └─ any decline/null after warm → THROW typed exception
cold seed required (first open / after invalidate) → seed the incremental
  machinery itself (tail reload / DB seedCold) → return
```

### Self-seeding incremental paths

| CLI | Cold seed today | Cold seed after |
|---|---|---|
| claude / codex / cursor / flashskyai (JSONL) | page window + background `_scheduleFullIndex` adapter parse | tail reader `_fullReload` via `lineAppend` (already exists; decode is worker-backed via `decodeJsonlLines`) |
| opencode (SQLite) | `seedFromFullParse` fed by adapter parse | new **`seedCold`** on `OpencodeHistoryIncrementalRefresher`: read all rows once, build fingerprint map + messages, pin `sessionId` |

`_scheduleFullIndex` (background full-index bootstrap) is **replaced** by
"warm the incremental seed". `fullIndex` and `workspaceSearchIndexes`
consumers read the warm incremental state's message list rather than a fresh
adapter parse.

### Errors

New typed exception, e.g. `AiHistoryIncrementalUnavailableError`, thrown after
warm when an incremental refresh declares it cannot proceed:

- opencode `_seen.isEmpty` (state exists but never aligned) → throw.
- opencode count fallback / schema mismatch (`_unsupported`) → throw.
- opencode deletion → **express incrementally**: extend `_mergeInPlace` to
  remove messages whose id vanished from the fingerprint rows, prune `_seen`.
- tail reader warm anchor loss / head fingerprint change → throw
  `AiHistoryAnchorLostError` (rewrite/compaction genuinely unable to follow
  incrementally). `_fullReload` remains for **cold** start only.

### Transient / no-blank

- Empty-result guard (`_loadOnce` `messages.isEmpty` + prior-content branch)
  stays; it is transient protection, not a full-parse fallback.
- Warm refresh failure → keep prior thread, surface `softReloadError` (seat
  already has `error`/`softReloadError` states; never blank).
- Cold load with an unresolvable store → `error` status + `errorMessage`.

## Component changes

- `services/cli/registry/capabilities/ai_history_capability.dart`
  - Interface: `seedFromFullParse` → `seedCold` (self-seeding, no adapter
    input) on `AiTranscriptIncrementalRefresher`; update docs.
- `services/cli/opencode/capabilities/history/ai_transcript.dart`
  - Implement `seedCold` (all-rows fingerprint + parse, pin `sessionId`).
  - Extend `_mergeInPlace` with deletion support; prune `_seen` on refresh.
  - Throw on count fallback / schema mismatch instead of `return null`.
- `services/session/history/ai_history_loader.dart`
  - Remove `_parseAndEnrich`, `_scheduleFullIndex`, executor/worker parse
    wiring, and the adapter-parse branch.
  - `_tryIncrementalLoad` / `_tryIncrementalRefresh` null after warm → throw.
  - Add cold-seed wait for opencode (seed before first refresh).
  - `fullIndex` reads the warm incremental state instead of a parsed index.
  - Keep mtime token cache, page-first, and all transient no-blank guards.
- `services/session/history/ai_transcript_tail_reader.dart`
  - Warm anchor loss / head rewrite → throw (cold `_fullReload` unchanged).
- `services/cli/opencode/capabilities/history/tool_output_backfill_enricher.dart`
  - Enricher runs inside **cold seed + warm refresh** over the diff (new /
    changed messages), closing the "until next full parse" latency gap.
- `cubits/ai_history_seat.dart`
  - Distinguish incremental-unavailable errors (message + retry affordance);
    map to `softReloadError` / `error` per decide above.

## Tests

- Update `ai_history_loader_test`: remove full-parse fallback assertions;
  assert typed errors on decline.
- Update opencode refresher tests: `seedCold` equality vs today's adapter
  result; deletion removes messages; count-fallback / schema → throw.
- Update tail reader tests: warm anchor loss → throw (`_fullReload` only cold).
- New: enricher runs on refresh (truncated part backfilled without full parse).
- Run per repo rules (`cd client && dart run tool/run_tests.dart`, `flutter
  analyze`).