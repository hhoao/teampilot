# Multi-CLI Subagent Side Resolvers

## Goal

Extend the existing [Subagent Preview Overlay](./2026-07-28-subagent-preview-overlay-design.md)
so Agent / Task-family tool rows resolve **side transcripts** for **every
launch-supported CLI** (Claude, flashskyai, Cursor, Codex, OpenCode) through the
same extensibility surface used for other CLI behavior. Overlay UI, seat epoch,
push/pop, depth cap, and parent-history refresh stay as in v1. Missing side data
still degrades to the tool-result synthetic preview.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Product scope | All five launch CLIs: Claude, flashskyai, Cursor, Codex, OpenCode |
| Architecture | First-class **`AiHistoryCapability`** on each `CliToolDefinition`; side resolve is part of that capability (not inflater `switch`, not adapter-owned attachments, not a parallel `Map<CliTool, …>` forever) |
| Failure policy | **C**: Claude and flashskyai **share** one Claude-compatible side implementation; Cursor / Codex / OpenCode each bind a **strict** resolver (no Claude `subagents/` fallback) |
| Tool-name gate | **Owned by each history capability** (`subagentToolNames`); host injects the seat CLI’s predicate into Chat UI; core may keep a union fallback for tests / no-scope |
| Side identity | Typed **`SubagentSideHandle`** (file vs session/logical) — do not overload a single nullable path string for OpenCode |
| Pipeline | Each resolver composes **extract link → locate side → parse** (shared helpers OK; god-class inflater not OK) |
| UI / overlay | Unchanged from v1 overlay design |
| Live updates | Follow parent history reload only |
| Path / IO | Workspace-bound `Filesystem` + `SessionHistoryContext` (SSH-safe) |
| Non-goals | Independent side-file watch; compose into preview; side-rail roster; TeamBus changes; personal Agent disallow changes |

## Problem

v1 inflate hard-codes Claude’s `{stem}/subagents/agent-*.jsonl` + meta
`toolUseId` inside `SubagentAttachmentInflater`. History locate/parse already
lives in a side map (`kAiHistoryProviders`) rather than on the CLI capability
graph. Other CLIs store nested work differently:

| CLI | Side layout | Hard link |
|-----|-------------|-----------|
| Claude | `{stem}/subagents/agent-*.jsonl` + `.meta.json` | meta `toolUseId` ↔ `toolCallId` |
| flashskyai | Same Claude-compatible dir layout (meta often missing) | meta when present; else `agentId` / degrade |
| Cursor (TeamPilot isolated HOME) | Sibling `{uuid}/{uuid}.jsonl` under `agent-transcripts` | Prefer `args.resume` UUID; else prompt ↔ sibling first user (normalized) |
| Codex | Sibling rollouts under `$CODEX_HOME/sessions/**` | `spawn_agent` → `agent_id` → `rollout-*-{id}.jsonl` |
| OpenCode | Same SQLite/JSON storage; child `session.parent_id` | `task` → `metadata.sessionId` / `<task id="ses_…">` |

Without a capability-owned pipeline, every new CLI forces host map edits and
inflater branches — the opposite of the registry model in `AGENTS.md`.

## Architecture

### Extensibility rule

**Adding or changing a CLI’s history / subagent linking = edit that CLI’s
`AiHistoryCapability` (and shared helpers it reuses). Do not special-case the
CLI in `AiHistoryLoader`, inflater, or Chat widgets.**

```
CliToolDefinition.capabilities
  └── AiHistoryCapability
        · locate(ctx) → AiTranscriptBundle?
        · adapter: AiTranscriptAdapter
        · subagentToolNames: Set<String>   // lower-case
        · subagentSideResolver: SubagentSideResolver

Parent history load / soft reload
        │
        ▼
registry.capability<AiHistoryCapability>(cli)
  locate → adapter.parse → List<AiMessage>
        │
        ▼
SubagentAttachmentInflater.inflate(
  messages,
  ctx,
  capability,                 // tool names + resolver
  parentHandle?,              // typed; null at root
)
  · for each toolCall where name ∈ capability.subagentToolNames:
      result = capability.subagentSideResolver.resolve(...)
      else degrade(tool result)
  · recurse with result.handle (maxDepth 8)
        │
        ▼
AiHistorySeat attachment index → SubagentPreviewOverlay (unchanged)
```

Migrate today’s `kAiHistoryProviders` / `aiHistoryDefaultAdapters()` into this
capability. Loader resolves providers **only** via `CliToolRegistry` (tests may
inject a fake capability / registry slice). A transitional thin wrapper around
the old map is acceptable only until all five tools are wired — the plan must
end with the map gone or reduced to a test double.

### Capability shape

```dart
abstract interface class AiHistoryCapability implements CliCapability {
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx);
  AiTranscriptAdapter get adapter;
  /// Lower-case tool names that open subagent preview for this CLI.
  Set<String> get subagentToolNames;
  SubagentSideResolver get subagentSideResolver;
}
```

| CLI | Capability notes | `subagentToolNames` (min) | Side resolver |
|-----|------------------|---------------------------|---------------|
| Claude | Own locate/adapter; **reuse** shared Claude-compatible side impl | `agent`, `task` | `ClaudeCompatibleSideResolver` |
| flashskyai | Own locate/adapter; **same** side impl instance/class as Claude | `agent`, `task` | same |
| Cursor | Own locate/adapter + strict side | `task`, `agent` (as emitted) | `CursorSideResolver` |
| Codex | Own locate/adapter + strict side | `spawn_agent` (+ `agent`/`task` if ever emitted) | `CodexSideResolver` |
| OpenCode | Own locate/adapter + strict side | `task` | `OpencodeSideResolver` |

Policy **C** is expressed as **shared implementation binding**, not a runtime
fallback chain: flashskyai’s capability points at the Claude-compatible
resolver; Cursor/Codex/OpenCode never call it.

### Typed side handle

```dart
sealed class SubagentSideHandle {
  const SubagentSideHandle();
}

final class SubagentFileHandle extends SubagentSideHandle {
  const SubagentFileHandle(this.path);
  final String path; // absolute, workspace FS
}

final class SubagentSessionHandle extends SubagentSideHandle {
  const SubagentSessionHandle(this.sessionId);
  final String sessionId; // e.g. OpenCode child ses_*
}
```

`AiSubagentAttachment.sidePath` (v1 string) becomes either:

- a derived display/debug field from `SubagentFileHandle.path`, or
- generalized to store `SubagentSideHandle?` (preferred for OpenCode recurse).

Inflater recurse **must** pass the typed handle into the next
`resolve(..., parentHandle: …)` so OpenCode does not invent fake JSONL paths.

### Resolver pipeline (per CLI, shared stages)

```dart
abstract interface class SubagentSideResolver {
  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required SubagentSideHandle? parentHandle,
  });
}

class SubagentSideResolveResult {
  const SubagentSideResolveResult({
    required this.messages,
    required this.handle,
  });
  final List<AiMessage> messages;
  final SubagentSideHandle handle; // next parent for nested inflate
}
```

Recommended internal stages (implementations may inline, but boundaries stay
testable):

1. **Extract link** (pure): `AiToolCallPart` → CLI-specific link id / resume UUID /
   session id / null.
2. **Locate side**: link + `ctx` + `parentHandle` → bytes / `AiTranscriptBundle` /
   null (Filesystem / SQLite only through existing history seams).
3. **Parse**: reuse **this capability’s** `adapter` (or the shared Claude-compatible
   JSONL parser when the side format matches that adapter).

Shared modules (by layout, not by “utils” dumping ground):

- `claude_compatible_subagent_layout.dart` — meta map + `agent-*.jsonl` paths
  (Claude + flashskyai).
- Optional small link parsers colocated with each `*_ai_transcript.dart`.

`SubagentAttachmentInflater` is **orchestration only**: name gate from
capability, depth, degrade, recurse, map to `AiSubagentAttachment`. Zero Claude
path joins.

### Tool-name gate (UI + inflate)

- **Inflate:** `capability.subagentToolNames.contains(normalizedName)`.
- **Chat chrome:** `AiToolSubagentActionsScope` (or seat host) supplies
  `bool isSubagentTool(String name)` from the **active seat CLI** capability so
  Codex `spawn_agent` and OpenCode `task` light up without a global hard-coded
  set driving product behavior.
- **`ai_message_core`:** keep a documented **union fallback**
  (`agent` / `task` / `spawn_agent`, case-insensitive) for unit tests and
  headless widgets without a scope; host production path must prefer the
  capability predicate. This supersedes the v1 overlay plan’s Agent/Task-only
  lock table.

### Per-CLI link details

#### Claude / flashskyai (`ClaudeCompatibleSideResolver`)

1. Prefer `{parentStem}/subagents/*.meta.json` where `toolUseId` == `toolCallId`.
2. Else `agentId` / `agent_id` from args or result.
3. Read `agent-{id}.jsonl`; parse Claude-compatible JSONL.
4. `handle` = `SubagentFileHandle(sideJsonlPath)`.

#### Cursor (`CursorSideResolver`)

1. Prefer resume / agent UUID from args →
   `{agent-transcriptsRoot}/{uuid}/{uuid}.jsonl`.
2. Else normalize Task prompt (strip timestamp / `user_query` wrappers); match
   sibling first user text; exclude parent stem. Among text matches, pick
   transcript whose file mtime (`Filesystem.stat`) is nearest the parent
   tool-call message time when known, else nearest parent transcript mtime.
   Same mtime tie or zero matches → null.
3. Parse via Cursor adapter.
4. `handle` = `SubagentFileHandle(childJsonlPath)`; nested resolve uses same
   transcripts root derived from that path.

#### Codex (`CodexSideResolver`)

1. From `spawn_agent` args/result take `agent_id`.
2. Under the parent rollout’s `$CODEX_HOME/sessions/**` tree, find
   `rollout-*-{agent_id}.jsonl` (reuse locate / `_rolloutId` patterns in
   `codex_ai_transcript.dart`).
3. Never probe Claude `subagents/`.
4. Parse via Codex adapter; `handle` = `SubagentFileHandle`.

#### OpenCode (`OpencodeSideResolver`)

1. From `task` state: `metadata.sessionId`, or `<task id="ses_…">` in output.
2. Load child message/part fragments from the **same** dataDir / DB as parent
   history (`SessionHistoryContext`), filtered by child session id.
3. If `session.parent_id` is available and mismatches parent, log; still prefer
   explicit tool sessionId.
4. `handle` = `SubagentSessionHandle(childSessionId)`; nested resolve uses that
   handle as parent (no fake file path).

## Error handling

| Case | Behavior |
|------|----------|
| Resolver returns null / read / parse fail | Degrade to tool-result; diagnostic log |
| Empty result and no side hit | `messages: []`; empty label; still openable |
| Cursor heuristic ambiguous / no match | Degrade (no Claude fallback) |
| OpenCode child missing | Degrade |
| Strict CLI near Claude dirs | Do **not** attempt Claude layout |
| Depth ≥ 8 | Degrade; stop recurse |
| Stack top missing after reload | Existing silent prune |
| Soft reload | Existing attachment epoch |
| Missing `AiHistoryCapability` for CLI | Loader fails loud (same class of error as missing adapter today) |

## Testing

- Capability wiring: each of five CLIs exposes `AiHistoryCapability`; loader uses
  registry (no production dependency on `kAiHistoryProviders` after migration).
- Unit per resolver: hit, miss; Cursor/Codex/OpenCode never touch `subagents/`.
- Shared Claude-compatible: meta hit; missing-meta + agentId; miss → null.
- Tool names: capability sets differ (Codex includes `spawn_agent`; OpenCode
  `task`); inflater honors capability set, not only core union.
- Typed handle: OpenCode nested inflate with `SubagentSessionHandle`.
- Host: seat CLI capability drives UI gate + inflate; epoch refresh unchanged.
- Synthetic fixtures per CLI (no mandatory live matrix).

## Out of scope

- Watching side files independently of parent history mtime
- Writing or continuing inside the subagent preview
- Listing all subagents in a side panel
- Changing TeamBus / roster semantics
- Enabling `Agent` in personal launches beyond current CLI disallow lists
- Runtime cross-CLI fallback chains (policy A/B rejected)
- Changing overlay chrome beyond injecting the capability tool-name predicate

## Relationship to v1

This spec **extends** resolution and **lifts history registration into the CLI
capability graph**. Overlay UI / navigation / read-only / depth / approach-2 lag
remain normative from the overlay design. On side-path linking and tool-name
ownership, **this** document wins; on Chat chrome structure, the overlay doc
wins.

The v1 overlay **implementation plan** Agent/Task-only alias lock is
**superseded**: tool names come from each `AiHistoryCapability`, with core union
as fallback only.
