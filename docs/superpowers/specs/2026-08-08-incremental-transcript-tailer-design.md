# Incremental transcript tailer (delta parsing) design

## Context

TeamPilot renders a Claude Code transcript live in the chat while the agent runs. The history loader (`client/lib/services/session/ai_history_loader.dart`) re-parses the **entire** parent transcript on every refresh: its cache token is the transcript mtime, which changes on every append, so each live refresh (polled every 750ms) runs `locate` → `adapter.parse(bundle)` over the full file (2.8 MB → every message re-`jsonDecode`d). Workflow runs multiply this: each re-inflate also re-parsed every agent transcript (~13 MB, ~330 ms of synchronous main-isolate work) until `ClaudeWorkflowResolver` gained an incremental (mtime, size)-keyed cache.

This spec replaces the "recompute everything on token change" model with an **incremental reader** that consumes the transcript as an append-only log: maintain a byte cursor, re-read only the appended tail, and reuse in-memory state for everything unchanged. It benefits **all** agent sessions, not just workflows, and removes the remaining pre-existing parent re-parse.

Established facts that drive the design:

- Claude transcripts (`*.jsonl`) are **append-only**; noise records (`progress`, `queue-operation`, `file-history-snapshot`, `permission-mode`) are dropped by `_appendFromEvent` in `claude_compatible_jsonl.dart`.
- A single assistant turn can stream across many JSONL lines sharing a logical `message.id` (`_logicalMessageId` + `_addOrMerge`); `finalizeAiMessagesForHistory` (`ai_message_core/lib/src/message.dart`) then coalesces adjacent assistants and finalizes tool status.
- `Filesystem` already exposes a feature-detected watch primitive (`FsWatcher.watchTree` → `FsTreeWatch`), with SFTP deliberately not implementing it.

## Goals

- **No full re-read / re-parse of unchanged bytes.** Live refresh is O(appended bytes) for the parent transcript, not O(file).
- **No main-isolate stall.** Delta work stays small; a full re-seek (rare: compaction / file replacement) is the only heavy path and can be a one-shot.
- **Incremental subagent attachments.** Reuse already-parsed workflow agents (resolver cache exists) and skip re-inflating unchanged tool calls.
- **Immediate, efficient live refresh.** Local backends watch the file and refresh on change instead of blind 750ms polling.

## Non-goals

- No change to the on-disk Claude transcript format (owned by the CLI, not us).
- No structured sidecar/index written by TeamPilot; the tailer parses the raw JSONL in place.
- No backward compatibility with the current `AiTranscriptAdapter` API — the interface is allowed to change (explicitly requested).

## Design overview

```
AiHistoryLoader.load
  → AiTranscriptTailer.refresh(ctx, force)      // NEW: cursor + delta parse
       ├─ unchanged (size == offset)  → cached finalized messages      [zero IO]
       ├─ grew                       → read tail, parse delta, merge   [O(appended)]
       └─ replaced / shrunk / first-line hash changed
                                     → full re-read, reset cursor      [rare]
  → incremental attachment refresh (reuse resolver cache + prior map)
```

## S1 — `AiTranscriptTailer` (new, `client/lib/services/session/ai_transcript_tailer.dart`)

One tailer per (session, member, cli), owned by the loader. State:

```dart
class AiTranscriptTailState {
  String? path;              // located transcript path
  String? pathKey;           // '<mtime>:<size>:<firstLineHash>' replacement guard
  int byteOffset;            // consumed prefix bytes
  List<AiMessage> raw;       // un-finalized messages accumulated so far
  List<AiMessage> finalized; // finalize(raw) — what the seat displays
  String? lastLogicalId;     // id of the tail message, for cross-batch stream merge
}
```

`Future<TailRefreshResult> refresh(SessionHistoryContext ctx, {required bool force})`:

1. **Locate** the current transcript path (reuse `AiHistoryCapability.locate` / `probePinnedTranscript`).
2. **Replacement guard**: `stat(path)` → `(mtime, size)`. Read the first line and hash it.
   - Full re-seek when: path changed, `size < byteOffset` (shrunk), or `firstLineHash` differs from cached (compaction rewrote the file in place to a same/larger size).
3. **Delta branch** when `size > byteOffset` and guard holds:
   - Read bytes `[byteOffset, size)` (or up to the last `\n`; keep a trailing partial line for the next round).
   - `LineSplitter` the tail; for each line call the existing `_appendFromEvent` into a fresh list **seeded with the carried `lastLogicalId`** so a streamed assistant turn that straddles the boundary merges (`_addOrMerge`).
   - Append resulting messages to `raw`; bump `byteOffset`; recompute `lastLogicalId`.
   - Recompute `finalized = finalizeAiMessagesForHistory(raw)` — full in-memory pass (no IO), which keeps cross-batch `tool_use` → `tool_result` correlation and adjacent-assistant coalescing correct.
4. **Unchanged branch** when `size == byteOffset` and guard holds: return cached `finalized`.
5. **force** → always full re-seek.

`_appendFromEvent` / `_addOrMerge` / `_logicalMessageId` are shared out of `claude_compatible_jsonl.dart` so the tailer and the full parser use the same line semantics. A new `AiTranscriptAdapter` method is added for incremental parsing (see S2).

## S2 — Loader integration (`ai_history_loader.dart`)

- `AiHistoryLoader` owns the `AiTranscriptTailer` per (session, member); `AiHistoryLoader.load` calls `tailer.refresh` instead of `locate` + `adapter.parse(bundle)`.
- Cache token becomes the tailer `pathKey` (`(mtime, size, firstLineHash)`) — the seat's existing token short-circuit keeps working, and a token change no longer implies a full re-parse.
- `force: true` (initial open, `invalidateAndReload`) → full re-seek.
- `AiTranscriptAdapter` (`ai_message_core/lib/src/transcript_adapter.dart`) gains an incremental entry point. All five adapters (claude, flashskyai, codex, opencode, cursor) keep a full `parse(bundle)`; only Claude/flashskyai (JSONL, append-only) wire the delta path first. Codex/opencode/cursor fall back to full parse on any change until their adapters support incremental — the tailer still saves them the unchanged-file case.

## S3 — Incremental attachments

- `ClaudeWorkflowResolver`'s (mtime, size)-keyed cache is already in place; unchanged workflow agents are not re-parsed (measured 477 ms → 12 ms warm).
- `SubagentAttachmentInflater` gains an optional `previous: Map<String, AiSubagentAttachment>`; a tool call whose attachment already exists and whose `sidePath` file `(mtime, size)` is unchanged is copied into the new map instead of re-resolved. Workflow runs reuse whole parsed runs; generic `agent`/`task` sub-agents are cheap either way.
- Resolution for changed/new calls still goes through the resolver cache, so a live run only pays for agents that actually grew.

## S4 — Local file watch instead of blind polling

- Reuse `FsWatcher.watchTree` (`client/lib/services/io/filesystem.dart`): when the located transcript path exists locally, watch it and call `softReload` on `FsChangeEvent`s (debounced, e.g. 150–250 ms).
- `AiHistoryLiveRefreshController` (`ai_history_live_refresh_controller.dart`) keeps its poll fallback for backends without `fs is FsWatcher` (SFTP) and for the case where the transcript path is not yet known.
- Improves both latency (change → refresh immediately) and idle cost (no polling when nothing writes).

## S5 — Edge cases

| Case | Detection | Handling |
|------|-----------|----------|
| Compaction / in-place rewrite | first-line hash differs, or `size < offset` | full re-seek (rare, one-shot) |
| Streaming assistant turn across refresh boundary | `lastLogicalId` carry | `_addOrMerge` continuation |
| `tool_use` in one batch, `tool_result` in the next | `finalizeAiMessagesForHistory(raw)` each refresh | correct by re-finalizing raw in memory |
| Partial trailing line (mid-write) | last byte is not `\n` | defer to next round |
| File replaced at same path + same size | first-line hash | full re-seek |
| Remote fs with no mtime / no watch | `pathKey` null / `fs is! FsWatcher` | full parse fallback (current behavior) |

## S6 — Tests

- **Tailer unit tests** (`test/services/session/ai_transcript_tailer_test.dart`):
  - append simulation: write file → refresh → append bytes → refresh; a counting `Filesystem` proves only tail bytes were read, and the message list is correct.
  - cross-batch streamed assistant merge (same `message.id` split at the boundary).
  - `tool_use`/`tool_result` split across batches finalizes correctly.
  - compaction (rewrite + first-line change) triggers full re-seek.
  - partial trailing line deferred, consumed next round.
  - `force: true` full re-seek.
- **Loader integration**: `softReload` reuses tailer state on unchanged token; `force` re-seeks; cache-token semantics preserved.
- **Attachment incremental**: inflater with `previous` map reuses unchanged agent attachments (extends `subagent_attachment_inflater_test.dart`).
- **Watch**: `AiHistoryLiveRefreshController` debounced change → `softReload`; poll fallback when `fs is! FsWatcher`.

## Rollout

- Land tailer + Claude/flashskyai delta path first (covers the reported jank); keep other adapters on full-parse-with-tailer (unchanged-file case still wins).
- Then incremental attachments + watch.
- Each step keeps the existing test suite green; measure with the real-session benchmark (cold vs warm resolve) before/after.
