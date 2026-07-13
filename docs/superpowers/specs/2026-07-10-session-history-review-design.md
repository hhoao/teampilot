# Session History Review (select ≠ connect) design

**Date:** 2026-07-10  
**Status:** Approved (spec review) — **product rules still in force**  
**Superseded (data model / parsers / review UI):** [AI Message Layer](2026-07-13-ai-message-layer-design.md) replaces `SessionHistoryTurn` / `SessionHistoryCapability` / turn-list widgets with `AiMessage` + `AiTranscriptAdapter` + `AiThread`. Sections below through **Rendering** describe the original design; use the 2026-07-13 spec for current types and paths.  
**Related:** `SessionResumeCapability`, `connectImmediately` / `ChatWorkbenchTerminalPlaceholder`, workbench center tabs (`SessionWorkbench` body), compose landing (`WorkspaceChatLanding`), [Session History Continue Chrome](2026-07-11-session-history-continue-chrome-design.md)

## Summary

Clicking an existing conversation in the workspace sidebar must **not** start a PTY. The session tab opens in a **review** body: read-only history parsed from each CLI’s on-disk transcript, plus a **slim compose** card (landing-style input with session-fixed chrome removed). Explicit submit starts the terminal and continues the chat.

Architecture: **select ≠ connect** as the interaction rule (unchanged). **Current read model:** per-CLI `AiTranscriptAdapter` implementations under `client/lib/services/cli/registry/capabilities/history/*_ai_transcript.dart` → `List<AiMessage>` via `AiHistoryLocator` / `AiHistoryLoader` / `AiHistoryCubit`; review UI is `AiThread` from `ai_message_ui` inside `session_history_review.dart`.

## Goals

| Goal | Description |
|------|-------------|
| No surprise launch | Opening an existing session never auto-connects |
| History-first review | Review shows prior turns when transcripts exist |
| Slim continue compose | Landing-like input without re-picking fixed session options |
| Extensible parsers | Five launch CLIs each implement history via registry capability |
| Mainstream-aligned parsing | Adapters follow known transcript schemas + fixtures, not guessed fields |

## Non-goals

- Live-tailing history UI while the PTY is running
- Project / worktree / expert / Team↔Simple chips on review compose (session-fixed). Permission and same-CLI preset/model continue chrome: see [Session History Continue Chrome](2026-07-11-session-history-continue-chrome-design.md)
- TeamPilot-owned message DB replacing CLI transcripts
- New workbench tab kind for history (stays inside session body)
- Vendoring Python/TS parser packages into Flutter (port schemas to Dart instead)

## Problem

Today `openWorkspaceSessionTab` → `requestOpenSession` defaults to `connectImmediately: true`, so sidebar clicks schedule PTY connect. Users avoid browsing conversations because selection implies launch (resource use / side effects).

A Start placeholder already exists when `!session.isRunning`, and `connectImmediately: false` is wired in tests — but the product path for “open existing” still auto-connects, and there is no transcript review surface.

## Interaction and session body states

`WorkbenchBody` with `active == session` hosts `SessionWorkbench`. Review is an **internal** sub-state of that surface, not a workbench tab kind.

| State | When | Center UI |
|-------|------|-----------|
| `review` | Selected; PTY not running | History list + slim compose |
| `connecting` | Connect in progress | Existing “starting…” |
| `running` | PTY connected | Existing terminal |

```
Any open-existing entry (see Wiring)
  → requestOpenSession(connectImmediately: false)
  → body = review (load history; no schedule connect)

Slim compose submit
  → connectWorkspaceSession → connecting → running
  → inject submitted message into the **selected member** session
  → clear compose; further interaction in terminal

Disconnect
  → return to review (reload or cache-hit history)
```

**Keep `connectImmediately: true` only for:** landing first-send create and automation dispatcher.

**v1 controls:** submit-as-start only. Empty compose submit is **disabled / no-op** (no separate Start button; no-message start is out of scope).

Slim-compose submit does **not** call `requestOpenSession(connectImmediately: true)`. It connects the **already-open** tab via `connectWorkspaceSession` (or equivalent explicit connect on that tab) and then injects.

### Team sessions

History and inject follow the workbench’s **`selectedMemberId`** (same member the terminal would show):

- `loadHistory` uses that member’s taskId / native id / runtime roots.
- Slim-compose submit connects and injects for that member only.
- Switching the selected member while in `review` reloads that member’s snapshot (cache key includes `memberId`).
- No aggregated multi-member transcript in v1.

### Review layout

```
SessionWorkbench (review)
┌─────────────────────────────┐
│  Read-only history          │
│  (Markdown assistant turns) │
├─────────────────────────────┤
│  Slim compose card          │
│  [continue chrome + input + │
│   attach/enhance/voice/send]│
│  Continue: identity (ro),   │
│  same-CLI model/preset,     │
│  permission [, team settings]│
│  Absent: project, worktree, │
│  team/simple, expert edit,  │
│  CLI switch, Start button   │
└─────────────────────────────┘
```

Reuse landing compose primitives (`ComposeTriggerField`, attach/enhance/voice) behind a review-specific shell — do not mount full `WorkspaceChatLanding`. Permission / same-CLI model continue chrome: [Session History Continue Chrome](2026-07-11-session-history-continue-chrome-design.md).

## Data model and `SessionHistoryCapability`

> **Superseded.** Live API: `AiMessage` / `AiTranscriptAdapter` in `client/packages/ai_message_core`, adapters in `client/lib/services/cli/registry/capabilities/history/`, loader/cubit in `client/lib/services/session/ai_history_*.dart` and `client/lib/cubits/ai_history_cubit.dart`. See [2026-07-13-ai-message-layer-design.md](2026-07-13-ai-message-layer-design.md). Transcript **locate** still uses `SessionHistoryContext` (`session_history_context.dart`).

Original normalized model (historical — UI consumed only this):

```dart
enum SessionHistoryRole { user, assistant, tool, system }

class SessionHistoryTurn {
  final SessionHistoryRole role;
  final String markdown;
  final DateTime? timestamp;
  final String? toolName; // when role == tool
  final bool collapsedByDefault;
}

enum SessionHistoryLoadStatus { ready, empty, error }

class SessionHistorySnapshot {
  final List<SessionHistoryTurn> turns;
  final SessionHistoryLoadStatus status;
  final String? errorMessage;
}
```

Capability (alongside `SessionResumeCapability` on `CliToolDefinition`):

```dart
abstract interface class SessionHistoryCapability implements CliCapability {
  Future<SessionHistorySnapshot> loadHistory(SessionHistoryContext ctx);
}
```

`SessionHistoryContext` reuses resume locating inputs: `fs`, `env`, `transcriptRoots`, `taskId` / `persistedNativeId`, `bucket`, workspace/session/member ids as needed. **Locate transcripts via TeamPilot session layout / launch env**, not solely the user’s global `~/.claude` (or equivalent) home tree.

### Building context without connect

Sidebar open must not call full `prepareLaunch` / shell connect. Provide a **read-only** context builder that:

1. Resolves the session’s runtime `Filesystem` and app data root (same as other workspace reads).
2. Computes layout paths (`transcriptSearchRoots`, isolated `CONFIG_DIR` / `CODEX_HOME` / `OPENCODE_DATA_DIR` / `CURSOR_CONFIG_DIR` **as they would be for this session on disk**) from persisted session + workspace + member bindings — without provisioning, writing launch plans, or scheduling PTY.
3. Fills `ResumeContext`-compatible fields for history locate (may share helpers with resume probing / `hasCliState`, but must be side-effect-free aside from reads).

If roots cannot be resolved (never launched, missing isolation dirs) → `empty`, not a connect attempt.

### Five adapters

| CLI | Primary source | Notes |
|-----|----------------|-------|
| claude | JSONL under session `transcriptRoots` / projects bucket | Align cc-transcript, claude-code-data, claude-devtools |
| flashskyai | JSONL under `workspaces/` layout in session roots | Dedicated adapter, not a silent Claude alias |
| codex | `rollout-*.jsonl` under session `CODEX_HOME` | Align agenthud schema, chat-history Codex source |
| opencode | **On-disk** under session `OPENCODE_DATA_DIR` (`storage/session/**/ses_*.json` and related message store the resume strategy already discovers) | Primary = disk parse in Dart. **Do not** require `opencode export` subprocess for v1. Optional later: export as a refresh aid only if disk shape proves incomplete |
| cursor | Chats / agent-transcript JSONL under session-isolated cursor config (`CURSOR_CONFIG_DIR` / fake HOME `.cursor`) | Align cursor-trace / tokenuse shapes; use manifest/`detectNativeId` chat id when present |

**Hard rule:** each adapter must implement against documented mainstream schemas and ship **fixture regression tests**. Skip unknown/noise lines (e.g. Codex `environment_context`); do not invent field mappings from memory.

Missing file → `empty`. Parse/IO failure → `error` with retry; never block slim compose or connect.

### History load UX

Host shows a local **loading** state (skeleton or inline progress) while `loadHistory` is in flight, then `ready` / `empty` / `error`. Loading must not look like session connect (“starting…”).

### Rendering

> **Superseded.** Review history renders via `AiThread` / `AiMessageParts` in `ai_message_ui` (tool cards, markdown parts). The notes below describe the original turn-list approach.

- Introduce `flutter_markdown_plus` **only in the presentation layer** for assistant (and optionally user) markdown.
- Parsers emit plain markdown strings; no UI package dependency in capabilities.
- Tool turns default to collapsed.

### Caching

- Cache snapshots by `sessionId` (+ `memberId` for team members).
- While `running`, do not require live history UI.
- On disconnect → review: reload, or reuse cache when transcript mtime unchanged.

## Wiring

**Open-existing** (all must use `connectImmediately: false`):

| Entry | Behavior |
|-------|----------|
| `openWorkspaceSessionTab` (sidebar) | Surface + review + `loadHistory` |
| Workspace search open | Same |
| Route deep-link `consumeChatWorkbenchRouteSession` | Same — today defaults to immediate connect; must flip |
| Any other “open persisted `AppSession`” helper | Audit and gate the same way |

**Still immediate connect:**

| Entry | Behavior |
|-------|----------|
| Landing create + first send | Unchanged |
| Automation dispatcher | Unchanged (`connectImmediately: true`) |
| Slim compose submit from review | Explicit connect + inject |

**UI / inject:**

| Concern | Behavior |
|---------|----------|
| Replace `ChatWorkbenchTerminalPlaceholder` | Review surface is the non-running body (no standalone Start CTA in v1) |
| Message inject | Reuse existing first-prompt / stdin inject paths for the **selected member** |
| Attach on slim compose | v1: same as landing — attach inserts `@path` (or equivalent) into the compose text that will be injected; no separate binary upload pipeline |

Do not hard-code CLI transcript formats in pages or `ChatCubit`. Chat/launch owns connect gating; history load is a capability call from the review host (or a thin session-history helper used by that host).

## Error handling

| Case | Behavior |
|------|----------|
| No transcript | `empty` copy; compose still works |
| Partial bad lines | Skip; keep best-effort turns |
| Hard parse/IO failure | `error` + retry; compose still works |
| SSH / remote fs | Use session `Filesystem`; timeout/IO → `error` |
| Connect fails after submit | Stay in review; keep compose text; show existing launch error |

## Testing

| Area | Cases |
|------|--------|
| Per-CLI adapters | Mainstream-shaped fixtures → expected turns (noise filter, tool fields) |
| Gate | Sidebar open → no PTY schedule; `connectImmediately: false` |
| Submit | Review submit → connect + message inject |
| UI | ready / empty / error; optional Markdown smoke |
| Regression | Landing create and automation still immediate-connect |

## Success criteria

1. Every open-existing path (sidebar, search, route deep-link, audited helpers) does not auto-start a terminal.
2. Review shows loading then history when available, empty/error otherwise, plus slim compose (no separate Start button in v1).
3. Submit starts the **selected member** session and continues with the typed message (including `@` attachments as text).
4. All five launch CLIs expose an `AiTranscriptAdapter` (registry map); a new CLI adds an adapter module only.
5. Parsers align with mainstream schemas and are fixture-tested; opencode reads session disk, not export subprocess.

## Implementation notes

- Gate change (`connectImmediately: false` on open-existing) ships with review UI in one change set — do not leave “open existing still auto-connects” after history UI lands.
- Extract slim compose from landing card concerns rather than forking a second full landing.
- Relate to workbench center tabs: history/review lives under `SessionWorkbench` only; no extra `WorkbenchTabKind`.
- **No backward compatibility:** delete `ChatWorkbenchTerminalPlaceholder` and any open-existing auto-connect path; do not keep dual UIs or feature flags.
- **No defensive programming:** fail loudly on programmer errors (missing capability on a launch CLI, invalid wiring). Soft statuses (`empty` / `error`) are only for missing/unreadable transcripts on disk, not for papering over incomplete adapters.
