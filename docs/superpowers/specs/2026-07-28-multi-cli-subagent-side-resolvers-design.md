# Multi-CLI Subagent Side Resolvers

## Goal

Extend the existing [Subagent Preview Overlay](./2026-07-28-subagent-preview-overlay-design.md)
so Agent / Task-family tool rows resolve **side transcripts** for **Cursor,
Codex, OpenCode, and flashskyai**, not only Claude. Keep the overlay UI, seat
epoch, push/pop stack, depth cap, and parent-history refresh model unchanged.
Missing or unreadable side data still degrades to the tool-result synthetic
preview.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Product scope | Claude (existing) + Cursor + Codex + OpenCode + flashskyai |
| Architecture | Pluggable `SubagentSideResolver` per CLI (not inflater `switch`, not adapter-owned attachments) |
| Failure policy | **C**: Claude and flashskyai share Claude-compatible resolver; Cursor / Codex / OpenCode are **strict** single resolvers (no Claude `subagents/` fallback) |
| UI / overlay | Unchanged from v1 overlay design |
| Live updates | Still follow parent history reload only |
| Tool-name gate | Expand aliases: at least `agent`, `task`, `spawn_agent` (case-insensitive) |
| Path / IO | Workspace-bound `Filesystem` + existing `SessionHistoryContext` (SSH-safe); no new global path shortcuts |
| Non-goals | Independent side-file watch; compose into preview; side-rail roster; TeamBus changes; personal Agent disallow changes |

## Problem

v1 inflate hard-codes Claude’s `{stem}/subagents/agent-*.jsonl` + meta
`toolUseId` link inside `SubagentAttachmentInflater`. Other CLIs store nested
work differently:

| CLI | Side layout | Hard link |
|-----|-------------|-----------|
| Claude | `{stem}/subagents/agent-*.jsonl` + `.meta.json` | meta `toolUseId` ↔ `toolCallId` |
| flashskyai | Same Claude-compatible dir layout (meta often missing) | meta when present; else `agentId` / degrade |
| Cursor (TeamPilot isolated HOME) | Sibling `{uuid}/{uuid}.jsonl` under `agent-transcripts` (no nested `subagents/`) | Prefer `args.resume` UUID; else prompt ↔ sibling first user (normalized) |
| Codex | Sibling rollouts | `spawn_agent` → `agent_id` |
| OpenCode | Same SQLite/JSON storage; child `session.parent_id` | `task` tool `state.metadata.sessionId` / output `<task id="ses_…">` |

Without pluggable resolvers, either Claude-only paths stay wrong for other CLIs,
or inflater accumulates forbidden CLI special-cases.

## Architecture

```
Parent history load / soft reload
        │
        ▼
CLI AiTranscriptAdapter.parse → List<AiMessage>
        │
        ▼
inflateSubagentAttachments(messages, ctx, cli)
  · resolver = registry.sideResolverFor(cli)   // policy C mapping
  · for each Agent/Task-family AiToolCallPart:
      prefer resolver.resolve(part, ctx)
      else tool-result synthetic messages
  · recurse into attachment.messages (maxDepth 8)
        │
        ▼
AiHistorySeat attachment index  (unchanged consumers)
        │
        └── SubagentPreviewOverlay stack  (unchanged)
```

### Resolver contract

Host-facing interface (name illustrative):

```dart
abstract class SubagentSideResolver {
  /// Returns side messages + optional sidePath / side key, or null to degrade.
  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required String? parentTranscriptPath,
  });
}
```

| CLI | Resolver | Notes |
|-----|----------|-------|
| Claude | `ClaudeCompatibleSideResolver` | Existing meta + JSONL logic moved out of inflater |
| flashskyai | **Same instance / class** | Shared layout; weaker link without meta |
| Cursor | `CursorSideResolver` | Strict; sibling UUID transcripts only |
| Codex | `CodexSideResolver` | Strict; sibling rollout via `agent_id` |
| OpenCode | `OpencodeSideResolver` | Strict; child session in same dataDir / DB |

Resolvers live next to existing history capabilities under
`client/lib/services/cli/registry/capabilities/history/`. Wire via
`CliToolRegistry` (or the history capability surface) so inflate receives the
resolver for the **session CLI**, not a global chain.

`SubagentAttachmentInflater` becomes orchestration only: tool-name gate, depth,
degrade, recurse. It must not embed Claude path joins.

### Tool-name gate

Extend `isAiSubagentToolName` / alias set so at least these resolve (trim +
lower-case):

- `agent`
- `task` (OpenCode + Cursor Task)
- `spawn_agent` (Codex)

Non-matching tools never enter inflate.

### Per-CLI link details

#### Claude / flashskyai (`ClaudeCompatibleSideResolver`)

1. Prefer list `{parentStem}/subagents/*.meta.json`, match `toolUseId` to
   `toolCallId`, open sibling `agent-{id}.jsonl`.
2. Else `agentId` / `agent_id` from args or result.
3. Parse with Claude-compatible JSONL parser.
4. `sidePath` = side JSONL path for nested inflate (still this resolver).

#### Cursor (`CursorSideResolver`)

1. Prefer hard link: resume / agent UUID from tool args (e.g. `resume`) →
   `{agent-transcriptsRoot}/{uuid}/{uuid}.jsonl`.
2. Else heuristic: normalize Task prompt (strip timestamp / `user_query`
   wrappers) and match sibling transcripts’ first user message; exclude parent
   stem; if multiple candidates, pick nearest by time; if zero or ambiguous
   beyond that rule → null (degrade).
3. Parse with existing Cursor history adapter / JSONL parser.
4. Nested Agent/Task rows re-resolve against the same transcripts root using the
   child path as parent context.

#### Codex (`CodexSideResolver`)

1. From `spawn_agent` args/result, take `agent_id`.
2. Map to sibling rollout path using the same layout the Codex history locator
   already understands.
3. No Claude `subagents/` probe.
4. Parse with Codex transcript adapter.

#### OpenCode (`OpencodeSideResolver`)

1. From `task` part state: `metadata.sessionId`, or parse `<task id="ses_…">`
   from output text.
2. Load child message/part fragments from the **same** OpenCode dataDir / DB the
   parent history used (`SessionHistoryContext`), filtered by child session id.
3. Optionally assert `session.parent_id` matches parent when available (log on
   mismatch; still prefer explicit tool sessionId).
4. Nested `task` rows resolve further child sessions the same way.
5. `sidePath` may be a logical key (child session id) if there is no single
   file path; recurse must pass enough ctx for the OpenCode resolver to reload
   that child (do not require a fake filesystem JSONL path).

### Inflate context

Extend inflate inputs beyond `fs` + `parentTranscriptPath` to include:

- Session **CLI** (selects resolver)
- Full **`SessionHistoryContext`** (or equivalent) so OpenCode can reuse
  dataDir / DB / session id without inventing new roots

## Error handling

| Case | Behavior |
|------|----------|
| Resolver returns null / read / parse fail | Degrade to tool-result attachment; diagnostic log only |
| Empty tool result and no side hit | `messages: []`; overlay empty label; still openable |
| Cursor heuristic ambiguous / no match | Degrade (no Claude fallback) |
| OpenCode child session missing | Degrade |
| Strict CLI accidentally near Claude dirs | Do **not** attempt Claude layout |
| Depth ≥ 8 | Degrade attachment; stop recurse |
| Stack top missing after parent reload | Existing silent prune |
| Soft reload | Existing attachment epoch refresh |

## Testing

- Unit per resolver: hit, miss, and strict “does not read Claude `subagents/`”
  for Cursor / Codex / OpenCode.
- Shared Claude-compatible: meta match; flashskyai-style missing meta + agentId;
  miss → null.
- Tool-name aliases: `spawn_agent`, `task`, `Agent` / `Task` casing.
- Inflater: selects resolver by CLI; depth cap; degrade path unchanged.
- Host: loader passes CLI/ctx; seat index populated for non-Claude fixtures.
- Minimal synthetic fixtures per CLI (no mandatory live matrix).

## Out of scope

- Watching side files independently of parent history mtime
- Writing or continuing inside the subagent preview
- Listing all subagents in a side panel
- Changing TeamBus / roster semantics
- Enabling `Agent` in personal launches beyond current CLI disallow lists
- Cross-CLI fallback chains (policy A/B rejected)

## Relationship to v1

This spec **extends** data resolution only. The overlay design’s UI, navigation,
read-only rules, nesting stack, and approach-2 refresh lag remain normative.
When both docs conflict on side-path resolution, **this** document wins for
multi-CLI linking; the overlay doc wins for Chat chrome.
