# Session Usage Storage Governance

**Date:** 2026-10-27
**Status:** Implemented
**Parent feature:** `docs/superpowers/specs/2026-10-26-agent-cli-usage-tracking-design.md`

## Goal

Keep the usage cache fast and bounded on long-lived home planes without
changing token extraction or event semantics. Compaction is non-destructive by
default; retention deletion is explicit.

## Scope

- Reuse `JsonUsageStore` per home plane and detect external file changes.
- Safe JSONL compaction: keep the latest revision per `requestId`.
- Optional retention cutoff for explicit deletion.
- Prune cursors for sources that disappeared after a complete scan.
- Incremental OpenCode V2 reads using `seq` / `time_updated`.
- Storage-maintenance dialog with stats and manual compaction.

## Non-goals

- gzip or on-disk compression.
- Changing the JSONL event schema.
- Automatic retention deletion.
- Backfilling old Codex model IDs.
- Rewriting cost history.

## Decisions

| Decision | Value |
|---|---|
| Compaction unit | Latest revision per `requestId` |
| Default compaction | Non-destructive; keeps all current events |
| Automatic compaction | After a successful sync when `lineCount >= 20_000` |
| Retention | API/UI explicit only; default off |
| Store reuse | One store/cursor/pricing store per `SessionUsageServices` |
| External change detection | File size + mtime fingerprint |
| Cursor prune | After a complete, error-free scan with targets |
| OpenCode V2 query | `seq > lastSeq OR time_updated > lastTime` |
| OpenCode V1 | Full read fallback |
| Cursor token | `oc|2|<maxTime>|<maxSeq>`; old tokens still parse |

## JSONL compaction

`JsonUsageStore.compact({int? retainAfterMs})`:

1. Load the latest index.
2. Drop events older than `retainAfterMs` when provided.
3. Write `{rev: 0, event: ...}` for each remaining latest event.
4. Use `Filesystem.atomicWrite`.
5. Reset the in-memory index, line count, and fingerprint.

`UsageCompactResult` reports:

- `beforeLines`
- `afterEvents`
- `removedLines`
- `removedEvents` (only retention deletions)

The current file is never partially rewritten; a failure leaves the old file.

`maybeCompact()` triggers compaction only above a line threshold. It is called
after a successful sync and is best-effort.

## Store cache

`SessionUsageServices` reuses the store instances for the current home plane.
`JsonUsageStore` fingerprints `(size, mtime)` before reads and reloads when the
file changed externally. This keeps a cache for repeated page loads while
remaining correct when another store instance appends.

`JsonUsageStore.stats()` exposes line count, event count, and size for the
maintenance dialog.

## Cursor pruning

`UsageCursorStore.prune(activeSourceIds)` removes cursors whose source no
longer exists. `SessionUsageSyncService` calls it only when:

- the scan was not cancelled;
- no source errors were recorded;
- at least one target existed.

`UsageSyncResult.prunedCursors` reports the count. Reappearing sources re-read
from the start; store upserts are idempotent.

## OpenCode incremental reads

V2 `session_message`:

- Detect `seq` and `time_updated` columns.
- Return `MAX(time_updated)` and `MAX(seq)` without scanning all rows.
- Query rows with `seq > lastSeq OR time_updated > lastTime`.
- If columns are absent, fall back to full read.
- Legacy V1 `message` remains full read.

The snapshot token is versioned. Old `oc|count|time|seq` tokens are parsed for
backward compatibility; the next save uses the new format.

Store replacement now allows final records to update when CLI-reported cost or
the model ID changes, so incremental OpenCode updates are not skipped.

## UI

`UsageFooter` gains a **Storage** action. `UsageMaintenanceDialog` shows:

- line count and event count;
- file size;
- a non-destructive **Compact events** action.

Compaction runs in the cubit, reloads the dashboard, refreshes stats, and shows
a toast. The dialog shows a local progress state and an inline error on failure.

## Testing

- Compaction keeps latest revisions and count metrics.
- Retention removes only old events.
- External store changes invalidate the cached index.
- Cursor prune removes only inactive sources.
- Sync prunes cursors only on a clean complete scan.
- OpenCode returns only new/updated rows; V1 fallback remains full.
- Cost/model updates replace final rows.
- Maintenance dialog compacts and shows failures.
- Full suite and analyzer.

## Risks

- An automatic compaction after sync rewrites a large file once; it is atomic
  and best-effort.
- Retention deletion is irreversible; the first UI exposes only non-destructive
  compaction, and the API requires an explicit cutoff.
- OpenCode timestamps that do not change on update can be missed; V2 `seq`
  catches new rows, and full read remains the fallback for legacy schemas.
- Fingerprint granularity on unusual filesystems may delay external-change
  detection; size changes still invalidate the cache.

## Follow-ups

1. Retention controls in the maintenance dialog.
2. Compaction scheduling/metrics and progress.
3. Cursor stats in the maintenance dialog.
4. SQLite usage store behind the same port for local planes.
