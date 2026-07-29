# Tool Result Enricher (shell stdout side channels)

**Date:** 2026-07-29  
**Status:** Approved

## Goal

Fill missing or truncated shell-tool stdout on History `AiToolCallPart.result`
from CLI-specific side channels, behind a capability-owned enricher hook.
Shell cards and other UI keep reading `result` only — no adapter or UI
special-casing per CLI.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Architecture | `ToolResultEnricher` on `AiHistoryCapability` (parallel to `SubagentSideResolver`) |
| Pipeline | `locate → parse → enrich → subagent inflate` inside `AiHistoryLoader` |
| Product scope | All five launch CLIs bind an enricher; Codex / OpenCode use NoOp |
| Cursor source | `projects/{slug}/terminals/*.txt` (not `store.db`) |
| Claude / flashskyai | Shared enricher: truncated `tool_result` → event-level `toolUseResult` |
| Overwrite policy | Only when result is missing/blank (`null`, empty, or whitespace-only) or truncation sentinel; never clobber full results |
| Cursor bind order | Walk shell tool parts in message order; each terminal file binds at most once |
| Capability wiring | Every history capability **explicitly** returns an enricher (Codex/OpenCode → NoOp); no interface default |
| UI / shell card | Unchanged (`2026-07-29-shell-tool-card-design.md`) |
| Path / IO | `SessionHistoryContext.fs` only (SSH-safe) |
| Live updates | Fold `terminals/` into existing History watch / cache paths (Cursor) |

## Problem

1. **Cursor** agent-transcripts typically emit `Shell` `tool_use` with
   `command` / `description` but **no** `tool_result`. Resume still shows
   output because Cursor persists it elsewhere (`terminals/*.txt`, encrypted
   `chats/.../store.db`). TeamPilot History only reads agent-transcripts →
   shell cards expand with `$ command` and empty body.
2. **Claude / flashskyai** usually include `tool_result.content`, but when
   truncated the rich `toolUseResult.stdout` on the JSONL event is ignored by
   the current parser.
3. **Codex / OpenCode** already map shell stdout into `result` from the primary
   transcript — no side channel needed today, but they must still sit on the
   same extension point so loaders never `switch (cli)`.

## Research summary

| CLI | Primary transcript stdout? | Side channel | Enricher |
|-----|----------------------------|--------------|----------|
| Cursor | Usually no | `terminals/*.txt` (`title`, `command`, body, `exit_code`) | Cursor terminals |
| Claude | Yes (partial when truncated) | Same JSONL event `toolUseResult` | Claude-compatible |
| flashskyai | Same as Claude | Same | Shared with Claude |
| Codex | Yes (`function_call_output`) | — | NoOp |
| OpenCode | Yes (`state.output`) | — | NoOp |

## Architecture

### Extensibility rule

Adding or changing shell-result side data for a CLI = edit that CLI’s
`AiHistoryCapability.toolResultEnricher` (and helpers it owns). Do **not**
branch in `AiHistoryLoader`, adapters’ UI consumers, or shell card chrome.

### Capability surface

```dart
abstract interface class ToolResultEnricher {
  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    required SessionHistoryContext ctx,
    required String? rootTranscriptPath,
    required AiTranscriptBundle? bundle,
  });
}

class NoOpToolResultEnricher implements ToolResultEnricher {
  const NoOpToolResultEnricher();
  @override
  Future<List<AiMessage>> enrich({...}) async => messages;
}

abstract interface class AiHistoryCapability implements CliCapability {
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx);
  AiTranscriptAdapter get adapter;
  Set<String> get subagentToolNames;
  SubagentSideResolver get subagentSideResolver;
  ToolResultEnricher get toolResultEnricher;
}
```

Each CLI history capability constructs its enricher explicitly (NoOp for
Codex/OpenCode).

### Loader seam

In `AiHistoryLoader.load` (and live refresh paths that parse):

```
messages = await cap.adapter.parse(bundle);
messages = await cap.toolResultEnricher.enrich(
  messages: messages,
  ctx: ctx,
  rootTranscriptPath: parentPath,
  bundle: bundle,
);
attachments = await inflater.inflate(...);
// cache stores enriched messages
```

### Shared helpers

- Identify shell tools / extract `command` + `description` via
  `DefaultAiShellToolTargetResolver` (do not duplicate name sets in enrichers).
- Immutable update: `part.copyWith(result: …, status: complete, isError: …)`
  then rebuild messages with updated parts.

## Cursor terminal enricher

### Locate directory

From `rootTranscriptPath` or `bundle.hints` cache paths pointing at
`…/agent-transcripts/{chatId}/{chatId}.jsonl`, resolve sibling:

```
…/projects/{slug}/terminals/
```

If missing / unlistable → no-op.

### File format

```
---
pid: …
cwd: "…"
command: "…"
title: "…"
status: succeeded|failed|…
started_at: ISO-8601
running_for_ms: …
---
<body stdout/stderr>
---
exit_code: N
elapsed_ms: …
ended_at: ISO-8601
---
```

Parser: two YAML front-matter fences; body between first closing `---` and
optional trailing fence; tolerate missing trailer.

### Matching

Candidates: shell-class `AiToolCallPart` whose `result` is missing or blank
(`null`, `''`, or whitespace-only after stringify).

Walk candidates in **message / part order**. For each candidate, pick the best
unbound terminal file:

1. `title == description` **and** normalized `command == args.command`
2. Else normalized `command` only (when description absent)
3. If several files still tie: prefer nearest `started_at` to tool/message
   timestamp if available; else latest `ended_at` / `started_at`

Each terminal file binds at most once (remove from pool after use).
Normalization: trim; unify line endings; unescape YAML double-quoted
`command` when needed.

### Write-back

- `result` = body text (trim trailing whitespace only as needed for display)
- `exit_code != 0` → `isError: true` (else leave `isError` false unless prior)
- `status` → `complete` when filling a previously empty result

### Watch / cache

Extend Cursor `locate` / `AiHistoryWatchMeta` so `terminals/` participates in
change detection and cache invalidation. Prefer raising `changeWatchRoot` to
`projects/{slug}/` (covers both `agent-transcripts/` and `terminals/`) and/or
adding terminal paths to `cacheTokenPaths` / token inputs so new `*.txt` files
invalidate History cache. Exact hint shape follows existing watch helpers.

## Claude-compatible enricher

Applies to Claude and flashskyai (shared implementation).

1. Index JSONL events that carry `toolUseResult` keyed by `tool_use_id` /
   tool use id from the same user `tool_result` event.
2. For shell (or any tool with empty/truncated result — **v1: shell tools and
   any tool whose `result` string matches truncation sentinel**):
   - Sentinel examples: content equals / contains `tool output truncated`
     (case-insensitive), matching known Claude truncation copy.
3. Replace `result` with `stdout` (append `stderr` if non-empty); set
   `isError` from `exitCode != 0` or existing `is_error`.
4. Non-truncated + existing result → unchanged.

Prefer re-reading the primary transcript bytes from `rootTranscriptPath` /
bundle fragment rather than changing `parseClaudeCompatibleJsonl` to smuggle
side maps — keeps adapters focused on message shape.

## Codex / OpenCode

`NoOpToolResultEnricher`. Document that primary transcript already supplies
`result`; future side channels plug in here without loader changes.

## Behavior matrix

| Case | Outcome |
|------|---------|
| Cursor Shell, no tool_result, matching terminal | `result` = terminal body |
| Cursor Shell, already has tool_result | unchanged |
| Cursor Shell, no matching terminal | unchanged (empty body in UI) |
| Claude Bash, full tool_result | unchanged |
| Claude Bash, truncated + toolUseResult.stdout | `result` replaced with stdout |
| Codex / OpenCode shell | NoOp |
| Enricher IO error | log diagnostic; return original messages |

## Non-goals

- Decrypting / parsing Cursor `chats/.../store.db`
- Changing shell-card UI chrome
- Capturing TeamPilot PTY buffer into History
- Independent long-lived watcher solely for terminals
- Enriching non-shell tools from terminals (v1 Cursor path is shell-matched)
- Inventing tool ids when Cursor omits them (correlation is title/command)

## Testing

- Unit: terminal file parser (happy path, missing trailer, garbage)
- Unit: Cursor enricher matching / exclusive bind / no overwrite / isError
- Unit: Claude enricher truncation vs non-truncation
- Loader: enrich called between parse and inflate; cache stores enriched list
- Fixture: Cursor transcript without `tool_result` + `terminals/*.txt` → shell
  card data has stdout; Claude `streamed_tools.jsonl`-style truncated event

## Implementation touchpoints

| Area | Path |
|------|------|
| Capability API | `client/lib/services/cli/registry/capabilities/ai_history_capability.dart` |
| Enricher interface + NoOp | `…/history/tool_result_enricher.dart` |
| Cursor parser + enricher | `…/history/cursor_terminal_tool_result_enricher.dart` (+ parse helper file if needed) |
| Claude shared enricher | `…/history/claude_compatible_tool_result_enricher.dart` |
| Wire capabilities | Cursor / Claude / flashskyai / Codex / OpenCode history capability classes |
| Loader | `client/lib/services/session/ai_history_loader.dart` |
| Cursor locate watch hints | `cursor_ai_transcript.dart` `locateCursorTranscript` |
| Tests | `client/test/services/cli/registry/capabilities/history/` + loader tests |
| Fixtures | extend `test/fixtures/session_history/cursor/` with `terminals/` |

## Relation to shell tool card

`2026-07-29-shell-tool-card-design.md` renders `$ command` + dim output from
`part.result`. Empty Cursor output is a **data** gap fixed by this enricher,
not by further UI work.
