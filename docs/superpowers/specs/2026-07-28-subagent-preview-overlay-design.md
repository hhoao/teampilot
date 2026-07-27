# Subagent Preview Overlay (Chat)

## Goal

Let users open Claude/Cursor-style **Agent / Task** tool rows from Chat into a
**stacked, read-only conversation preview** inside the Chat workbench. Prefer
side-channel subagent transcripts when present; otherwise degrade to the tool
result text. Refresh the preview when the **parent** history reloads (inflate
with the main transcript — approach 2). Do not mount nested transcripts inline
on the tool row, and do not create a new session tab.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Entry surface | Agent / Task family tool rows only (case-insensitive name set + aliases) |
| Navigation | Chat-area **overlay** push/pop stack (not session tab, not editor tab) |
| Interaction | Read-only; **no** compose into the subagent |
| Live updates | Follow parent history live reload / soft reload (no dedicated side-file watch) |
| Data model | Inflate attachments during parent history load → `toolCallId → AiSubagentAttachment` |
| CLI scope (v1) | All CLIs; missing side transcript → synthetic preview from tool result |
| Nesting | Overlay can open Agent/Task again → push another layer (depth-capped inflate) |
| Path / IO | Workspace-bound `Filesystem` only (SSH-safe); no `LocalFilesystem` fallback |
| Non-goals | Stop subagent; side-rail roster; new `ChatTab` / session; TeamBus changes; per-side-file watcher |

## Problem

1. Agent / Task tool rows look like ordinary tools; the real subagent turn stream
   often lives in a **sibling** JSONL (e.g. Claude `…/{uuid}/subagents/agent-*.jsonl`),
   not inlined in the parent transcript.
2. Inlining the full nested transcript under the tool row is hard to scan and
   fights the existing tool expand / file-open chrome.
3. Hard-coding Claude-only paths in the widget would block Cursor / flashskyai /
   degrade-only CLIs and would not reuse the History seat reload pipeline.

## Architecture

```
Parent transcript load / live reload
        │
        ▼
CLI AiTranscriptAdapter.parse → List<AiMessage>
        │
        ▼
inflateSubagentAttachments(messages, ctx)
  · for each Agent/Task AiToolCallPart:
      prefer side JSONL → parse → messages
      else tool result text → synthetic assistant message
  · recurse into those messages (max depth)
        │
        ▼
AiHistorySeat (+ attachment index)
  Map<toolCallId, AiSubagentAttachment>
        │
        ├── SessionHistoryThread (main)
        │     Agent/Task row → onOpenSubagent(toolCallId)
        │
        └── SubagentPreviewOverlay stack
              List<toolCallId> (display looks up current seat index)
              read-only message list, no compose
              nested Agent/Task → push
              back → pop / clear
```

Accepted lag (approach 2): if a side transcript grows while the parent JSONL is
unchanged, the preview may stay stale until the next parent history reload.

### Core types (`ai_message_core`)

```dart
enum AiSubagentAttachmentSource { sideTranscript, toolResult }

class AiSubagentAttachment {
  const AiSubagentAttachment({
    required this.toolCallId,
    required this.messages,
    required this.source,
    this.title,
    this.sidePath,
  });

  final String toolCallId;
  final List<AiMessage> messages;
  final AiSubagentAttachmentSource source;
  final String? title;
  final String? sidePath;
}

bool isAiSubagentToolName(String toolName); // Agent / Task (+ alias table)
```

Inflation helpers may live in core (pure) or host services that take `Filesystem`
+ parent transcript path; keep CLI path layout knowledge next to existing history
capabilities where possible.

### UI (`ai_message_ui`)

- `AiToolSubagentActions` / `AiToolSubagentActionsScope` — parallel to
  `AiToolFileActions`; exposes `onOpenSubagent(String toolCallId)` (and optionally
  the part for chrome).
- `AiToolCallPartView` — when `isAiSubagentToolName` and actions present, render a
  tappable Agent/Task summary (description / title snippet). Chevron / args expand
  stays independent (same split as file-target rows).
- `SubagentPreviewScaffold` — back chrome + read-only message thread (reuse part
  registry / grouping). **No** compose footer. Re-inject subagent + file actions
  so nested Agent and Read/Write still work.

### Host (`client/lib`)

- Run `inflateSubagentAttachments` on the History load path after parse, before
  publishing seat state; store the index on `AiHistorySeat` (or an adjacent
  seat projection that reloads atomically with messages).
- `SubagentPreviewController` — stack of `toolCallId`; push / pop / clear;
  on seat refresh, drop stack entries missing from the new index (pop to last
  valid ancestor, or clear).
- `session_chat_view` — wrap thread with subagent actions; stack overlay above
  the main transcript when non-empty.

### Side transcript resolution (Claude / compatible)

Prefer Orca-aligned layout:

```
{parentTranscriptDir}/{parentStem}/subagents/agent-{id}.jsonl
```

Resolve `id` from tool args / result (`agent_id`, `agentId`, or equivalent).
Parse with the existing Claude-compatible JSONL parser when bytes are available.

Other CLIs may supply an optional side-path hook on their history capability; if
absent or file missing → tool-result degrade.

## Error handling

| Case | Behavior |
|------|----------|
| Side file missing / read fail | Degrade to tool-result attachment; log only |
| Empty result and no side file | Attachment with `messages: []`; scaffold shows l10n empty label; still openable |
| Open unknown `toolCallId` | AppToast; do not push |
| Stack top id disappears after reload | Silent prune to last id still in index, else clear overlay |
| Inflate depth limit (8) | Create degrade attachments at max depth; do not recurse further |
| Remote / SSH | Same workspace `Filesystem` as parent history |
| Claude side match | Prefer `agent-*.meta.json` `toolUseId` → `toolCallId`; else args `agentId` |
| Soft reload rebuild | Seat state includes attachment epoch so open overlay refreshes with parent reload |

## Side transcript resolution (Claude / compatible)

Prefer Orca-aligned layout:

```
{parentTranscriptDir}/{parentStem}/subagents/agent-{id}.jsonl
{parentTranscriptDir}/{parentStem}/subagents/agent-{id}.meta.json
```

Primary link: list meta files, match `toolUseId` to the tool row’s `toolCallId`, then
read the sibling JSONL. Secondary: `agent_id` / `agentId` from tool args.
Parse JSONL with the existing Claude-compatible parser when bytes are available.

Other CLIs may supply an optional side-path hook on their history capability; if
absent or file missing → tool-result degrade.