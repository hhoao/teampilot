# AI Message Layer (assistant-ui-aligned) design

**Date:** 2026-07-13  
**Status:** Approved (spec review)  
**Related:** [Session History Review](2026-07-10-session-history-review-design.md), [Session History Continue Chrome](2026-07-11-session-history-continue-chrome-design.md), open-source reference `assistant-ui` (`packages/core` message + ExternalStore runtime)

**Supersedes** the 2026-07-10 **data model / `SessionHistoryCapability` / review bubble UI** sections. Product rules from that spec and continue-chrome (**select ≠ connect**, slim compose, single selected member, History↔Terminal) remain in force.

## Summary

Introduce a **TeamPilot-owned AI message layer** as two Dart packages under `client/packages/`, modeled after assistant-ui’s core/runtime/UI split:

1. **`ai_message_core`** — `AiMessage` / parts / `AiThreadRuntime` / `ExternalStore` / adapter **interfaces**
2. **`ai_message_ui`** — Flutter Thread → Message → Part history UI (mainstream chat quality)

**CLI transcript adapters live in TeamPilot** (CLI registry / `services/cli/…`), implementing `AiTranscriptAdapter` from core. They are **not** a third package.

TeamPilot is the **composition root**: locate on-disk transcripts, run adapters, bind runtime, keep slim compose + PTY connect/inject. CLI transcripts stay the **authoritative** history store. There is **no** TeamPilot message DB and **no** live-tail while the PTY runs.

This **replaces** the existing `SessionHistoryTurn` / `SessionHistoryCapability` / session-history review widgets. No backward compatibility.

## Goals

| Goal | Description |
|------|-------------|
| Unified message model | All agent history surfaces as `AiMessage` + parts |
| Best-in-class review UI | Thread timeline aligned with assistant-ui / ChatGPT-class patterns |
| Package isolation | Core + UI reusable and testable without the app shell |
| Extensible runtime | ExternalStore so future stores (live-tail, merge) swap without UI rewrite |
| CLI-agnostic packages | Core/UI never import CLI schemas; adapters stay in app/registry |
| Clean break | Delete old history types and UI; no shims |

## Non-goals

- Live-tailing structured history while PTY is running
- TeamPilot-owned persistent message database
- Multi-member aggregated timeline
- Folding TeamBus mail into the history thread (Mailbox stays separate)
- Moving slim compose, PTY, connect/inject, or **CLI parsers** into packages
- A separate `ai_message_adapters` package (or per-CLI packages)
- Porting assistant-ui edit / branch / cloud / full composer primitives
- Compatibility with `SessionHistoryTurn` or old capability return types

## Problem

History today is three disconnected representations:

1. CLI transcripts → lossy `SessionHistoryTurn` (markdown string + role)
2. Live Alacritty scrollback (ANSI, not structured)
3. TeamBus `TeamMessage` (coordination, not user↔agent chat)

`SessionHistoryTurn` cannot express tool call/result parts cleanly, UI quality is limited, and the model is stuck inside TeamPilot app code—hard to evolve toward assistant-ui-class Thread/Part rendering or alternate stores.

## Architecture

```
CLI transcript (disk)
        │
        ▼
TeamPilot adapters (CLI registry)
  AiTranscriptAdapter.parse ──► List<AiMessage>
        │
        ▼
ai_message_core
  ExternalStoreAiThreadRuntime.setMessages(...)
  AiThreadRuntime (messages / status / changes)
        │
        ▼
ai_message_ui
  AiThread → AiMessageView → AiMessageParts
        │
        ▼
TeamPilot app
  locate + wire + slim compose + connect/inject
```

| Unit | Owns | Must not |
|------|------|----------|
| `ai_message_core` | Models, normalize, runtime, adapter **interfaces**, status enums | Flutter, CLI formats, filesystem, TeamPilot models |
| `ai_message_ui` | Thread/Message/Part widgets, markdown, tool cards, theme hooks | Locate transcripts, start PTY, know CLI schemas |
| TeamPilot adapters | Claude / flashskyai / Codex / OpenCode / Cursor parsers + fixtures | Depend on `ai_message_ui`; invent parallel message types |
| TeamPilot app shell | Path locate, member selection, cubit, slim compose, l10n | Re-implement bubble chrome; bypass `AiMessage` |

### Dependency graph

```
ai_message_ui ──────────► ai_message_core
teampilot (app) ─────────► ai_message_core, ai_message_ui
  └── CLI adapters ──────► ai_message_core only
```

## Core model (`ai_message_core`)

### Parts and messages

Align with assistant-ui’s message part model (subset):

```dart
enum AiRole { user, assistant, system }

sealed class AiMessagePart {}

class AiTextPart implements AiMessagePart {
  final String text;
}

class AiToolCallPart implements AiMessagePart {
  final String toolCallId;
  final String toolName;
  final Map<String, Object?>? args;
  final String? argsText;
  final Object? result;
  final bool isError;
}

class AiReasoningPart implements AiMessagePart {
  final String text;
}

enum AiMessageStatus { complete, incomplete, cancelled }

class AiMessage {
  final String id;
  final AiRole role;
  final List<AiMessagePart> parts;
  final DateTime? createdAt;
  final AiMessageStatus status;
}
```

**Rules:**

- There is **no** `tool` role. Tools are parts on assistant messages (assistant-ui aligned).
- Transcript events that look like `tool_result` on **user** turns (Claude/Cursor-style) must be **correlated by tool call id** onto the matching assistant `AiToolCallPart.result` (or `isError`). Do **not** emit tool-only user turns as `AiMessage`s.
- `AiReasoningPart` + UI dispatch exist in v1; adapters **need not** emit reasoning until a CLI source provides it cleanly.
- Stable `id`s: adapters should derive deterministic ids from transcript event ids when present; otherwise hash `(adapterId, ordinal, role, fingerprint)`.
- Optional **`ThreadMessageLike`** input shape (`content: String | List<parts>`) exists only as an adapter convenience; the store always holds normalized `AiMessage`.

### Runtime (ExternalStore)

```dart
enum AiThreadStatus { idle, loading, empty, error }

abstract class AiThreadRuntime {
  List<AiMessage> get messages;
  AiThreadStatus get status;
  String? get errorMessage;
  /// Pure-Dart notify API (e.g. `Stream<void>`). Must not depend on Flutter
  /// (`Listenable` / `ValueNotifier`) so `ai_message_core` stays Flutter-free.
  Stream<void> get changes;
}

class ExternalStoreAiThreadRuntime implements AiThreadRuntime {
  void setMessages(List<AiMessage> messages); // → idle (or empty if list empty)
  void setLoading();
  void setError(String message);
  void setEmpty();
}
```

App code never mutates message lists in place; it replaces via store methods. UI binds only to `AiThreadRuntime`.

### Adapter interface (declared in core, implemented in TeamPilot)

```dart
class AiTranscriptFragment {
  final String name; // e.g. primary jsonl path basename or logical key
  final List<int> bytes;
}

class AiTranscriptBundle {
  final String adapterId;
  final List<AiTranscriptFragment> fragments;
  final Map<String, String> hints; // optional locate hints (native id, etc.)
}

abstract class AiTranscriptAdapter {
  String get id;
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle);
}
```

Multi-file CLIs (Codex, OpenCode) use multiple fragments; single-file CLIs use one. Adapters parse **bytes only**—path open/locate stays in `AiHistoryLocator`.

## TeamPilot adapters (in-app)

Replace `SessionHistoryCapability` / `SessionHistoryTurn` with implementations of `AiTranscriptAdapter` under the CLI registry (e.g. `client/lib/services/cli/registry/…/history/` or successor path). Keep **one module per CLI** inside the app tree—not separate packages.

| Adapter id | Source format (existing knowledge) |
|------------|--------------------------------------|
| `claude` | projects bucket JSONL |
| `flashskyai` | workspaces JSONL (Claude-like) |
| `codex` | `rollout-*.jsonl` under session CODEX_HOME |
| `opencode` | `ses_*.json` + message store |
| `cursor` | isolated chat/transcript JSONL |

**Parsing policy:** skip individually corrupt events when safe; if the file is unusable, throw → loader maps to `setError`. Prefer mainstream schemas + fixtures over guessed fields (same bar as the 2026-07-10 history plan).

**Fixtures / tests:** remain under `client/test/` (migrate golden expectations from `SessionHistoryTurn` → `AiMessage`). Registry maps `CliTool` → adapter instance.

## UI package (`ai_message_ui`)

Composition (assistant-ui primitives, review-only subset):

| Widget | Responsibility |
|--------|----------------|
| `AiThread` | Bind runtime; switch loading / empty / error / message list via **injected builders / widgets** (no hardcoded app copy) |
| `AiMessageView` | Role-based layout (user vs assistant vs system) |
| `AiMessageParts` | Dispatch parts; honor `partBuilders` overrides |
| `AiTextPartView` | Streaming-safe Markdown (stable blocks; unclosed fences do not crash or thrash layout) |
| `AiToolCallPartView` | Collapsible card: name, args, result, error |
| `AiReasoningPartView` | Collapsed-by-default reasoning text |

**Theming:** `AiMessageTheme` / `ThemeExtension` with neutral defaults; TeamPilot injects brand tokens.

**Copy / chrome:** `AiThread` takes builders (or prebuilt widgets) for empty, error (+ retry callback), and loading. Packages must not depend on TeamPilot l10n.

**List behavior:** index-based API suitable for later virtualization. **Preserve** the existing review “load older” UX: app owns windowing/pagination and calls `setMessages` with the expanded window; core does not embed pagination policy.

**Out of package:** slim compose, attach/enhance/voice, connect/inject, History↔Terminal toggle chrome (app / existing continue-chrome specs).

## TeamPilot integration

### Replace surface

| Remove | Replacement |
|--------|-------------|
| `SessionHistoryTurn`, `SessionHistorySnapshot`, `SessionHistoryCapability` | `AiMessage` + in-app `AiTranscriptAdapter`s + runtime |
| `session_history_turn_list.dart` / `session_history_turn_tile.dart` (and related) | `AiThread` from `ai_message_ui` |
| Capability return types wired to markdown turns | `parse` → `List<AiMessage>` |

Keep / adapt:

- **Select ≠ connect** and review vs terminal workbench states ([2026-07-10](2026-07-10-session-history-review-design.md))
- Slim compose + continue chrome ([2026-07-11](2026-07-11-session-history-continue-chrome-design.md))
- Transcript **locate** logic (`transcriptSearchRoots`, resume-shaped context) — rename/refactor into `AiHistoryLocator` producing `AiTranscriptBundle`
- Single **selected member** scope only

### App services

```
AiHistoryLocator  → SessionHistoryContext-like inputs → AiTranscriptBundle | missing
AiHistoryLoader   → locator + CliTool→adapter map + ExternalStoreAiThreadRuntime
AiHistoryCubit    → owns runtime; reload on open review / member switch; generation token cancels stale loads;
                    exposes load-older by widening the in-memory window and setMessages (same UX as today’s turn list)
```

On disconnect → return to review → reload (or mtime cache hit on located files, if retained).

### pubspec

```yaml
# client/pubspec.yaml
dependencies:
  ai_message_core:
    path: packages/ai_message_core
  ai_message_ui:
    path: packages/ai_message_ui
```

## Interaction (unchanged product rules)

| State | Center UI |
|-------|-----------|
| `history` / review | `AiThread` + slim compose |
| `connecting` | Existing starting UI |
| `terminal` / running | Alacritty terminal |

Open-existing → `connectImmediately: false` → review loads messages.  
Slim compose submit → connect selected member → inject → terminal.  
No aggregated multi-member transcript.

## Error and empty states

| Condition | Runtime | UI |
|-----------|---------|-----|
| No transcript / empty parse | `empty` | App l10n empty state |
| Locate or parse failure | `error` + message | Error panel + optional retry |
| In-flight load | `loading` | Progress / skeleton |
| Stale load after member switch | Ignored via generation token | Shows latest member only |

## Testing

| Layer | Coverage |
|-------|----------|
| `ai_message_core` | Normalize Like→Message; store state machine; id stability |
| `ai_message_ui` | Widget tests: statuses, tool collapse, markdown smoke |
| TeamPilot adapters | Per-CLI fixtures → golden `AiMessage` trees |
| App loader/cubit | Locator + loader with mock filesystem; stale-load cancellation |

## Success criteria

1. Opening an existing session shows a parts-based Thread UI for the selected member’s CLI transcript without starting a PTY.
2. Tool calls render as structured cards, not opaque markdown blobs (when transcript provides structure).
3. Adding a sixth CLI means a new in-app adapter module + locate wiring—**no** changes to core message types or Thread widgets for the common case.
4. Zero remaining references to `SessionHistoryTurn` / `SessionHistoryCapability` in app code.
5. `ai_message_core` and `ai_message_ui` build and test in isolation.

## Implementation order (guidance for plan)

1. Scaffold `ai_message_core` + `ai_message_ui` + path deps
2. Core models + ExternalStore + normalize + adapter interfaces
3. Rewrite Claude (then other CLI) history modules as `AiTranscriptAdapter` → `AiMessage`
4. UI Thread/Message/Parts + markdown + tool card
5. App locator/loader/cubit; swap review body to `AiThread`
6. Delete old history types/UI; update tests and docs

## Open decisions resolved in this spec

| Topic | Decision |
|-------|----------|
| Scope | Model + History UI together |
| Authority | CLI transcripts; no live-tail; no message DB |
| Member scope | Selected member only |
| Package split | **core + ui only**; CLI adapters stay in TeamPilot |
| Runtime | ExternalStore (assistant-ui-aligned), full fidelity |
| Parts v1 | `text`, `tool-call` (+ result correlation onto same part), `reasoning` type/UI reserved (adapters optional) |
| Compatibility | None — delete old history types/UI |
| Compose | Stays in TeamPilot |
| TeamBus | Stays in Mailbox |
