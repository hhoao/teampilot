# Ask-user-question: per-CLI answer capability (design)

**Date:** 2026-08-03  
**Status:** Approved for planning  
**Scope:** Make chat-side AskUserQuestion answering correct across CLIs: capability-gated UI, Claude-family PTY answers, OpenCode SDK reply via Bus pending store, optimistic dismiss, generic l10n.

## Problem

TeamPilot already surfaces structured ask-user questions in Chat (via `/agent-status` → `AgentAttentionCubit` → interactive card). Detection is multi-CLI (Claude-family hooks + OpenCode `question.asked`), but answering is a single Claude TUI assumption: inject option digit + Enter over PTY.

That creates three failures:

1. **OpenCode** can render a card but cannot be answered correctly (needs `client.question.reply` with labels + `request_id`, not PTY digits). The plugin already forwards `request_id`; the Dart event model drops it.
2. **Cursor** has no structured ask tool; OSC-title waiting correctly falls back to the generic banner — but product copy still says “Claude is asking…”.
3. **UX**: after a successful click the card waits for a later hook to clear attention; failures are silent; late hooks can race.

## Goals

1. **Per-CLI answer capability** on the CLI registry (same pattern as `TurnInterruptCapability`): declare whether a CLI supports structured ask, in-chat answer, and in-chat multi-select.
2. **Correct answer ports:**
   - Claude / flashskyai / Codex → PTY picker keystrokes (existing behavior, behind capability).
   - OpenCode → Bus pending answer + agent-status plugin poll + `client.question.reply` / `reject` (no dependency on `opencode serve`).
   - Cursor → no in-chat card (`supportsInChatAnswer = false`).
3. **Card gating** via a pure policy function (capability + question shape), not ad-hoc branches in the banner widget.
4. **Optimistic dismiss** after a successful local answer handoff: set attention to `working` while retaining ask payload for reconciliation; ignore same-`askRequestId` late waiting; restore on `reply_failed`.
5. **Generic l10n** for the ask title and answer failure strings (no Claude brand lock-in).
6. **OpenCode multi-select / multi-question** interactive card when capability allows (label-array reply). PTY-family multi-select remains banner → terminal.

## Non-goals

- Structured ask / in-chat answer for Cursor (plain-text OSC title path unchanged).
- In-chat multi-select for PTY-family CLIs.
- Changing history-continue / follow-up gate semantics beyond existing `permissionWaiting` block.
- Reworking permission-approval flows unrelated to AskUserQuestion / `question.asked`.
- Calling OpenCode’s HTTP `/api/session/.../question/.../reply` from Dart against a separate serve process.

## Support matrix

| CLI | Structured ask | In-chat answer | In-chat multi / multi-question | Answer kind |
|-----|----------------|----------------|--------------------------------|-------------|
| Claude | yes | yes | no (banner) | `ptyPicker` |
| flashskyai | yes | yes | no (banner) | `ptyPicker` |
| Codex | yes (if tool emits Claude-shaped payload) | yes | no (banner) | `ptyPicker` |
| OpenCode | yes (`question.asked`) | yes | yes | `pluginSdkReply` |
| Cursor | no | no | — | `none` |

## Architecture

### Capability

New `AskUserQuestionCapability` under `client/lib/services/cli/registry/capabilities/`:

```dart
enum AskUserAnswerKind { ptyPicker, pluginSdkReply, none }

abstract interface class AskUserQuestionCapability implements CliCapability {
  bool get supportsStructuredAsk;
  bool get supportsInChatAnswer;
  bool get supportsMultiSelectInChat;
  AskUserAnswerKind get answerKind;
}
```

Wire onto each `CliToolDefinition` (same registration path as `TurnInterruptCapability`). UI and answer facade resolve via `CliToolRegistry.capability<AskUserQuestionCapability>(cli)`.

### Data flow

```
CLI tool / question
  → hook or OpenCode plugin POST /agent-status
  → AgentStatusNormalizer (keep questions + askRequestId [+ nativeSessionId for OpenCode])
  → AgentAttentionCubit.applyEvent (waiting + payload)
  → AgentPermissionAttentionBanner
       → shouldShowAskUserQuestionCard(cap, questions) ?
            AskUserQuestionCard : generic banner
  → user answers / cancels
  → AskUserQuestionAnswerFacade (by answerKind)
       ptyPicker        → write digit/Esc to seat PTY
       pluginSdkReply   → AskUserAnswerPendingStore.put
       none             → no-op / open terminal only
  → on local success: set attention working (retain lastEvent + dismissed askRequestId)
  → OpenCode plugin: poll GET /ask-user-answer?request_id=… → client.question.reply|reject
  → on reply_failed: restore waiting from retained lastEvent + surface error
```

### Event / attention model

Extend `AgentStatusEvent` (and thus `AgentSeatAttentionEntry.lastEvent`) with:

- `askRequestId` (`String?`) — from Claude tool_use id when useful, required for OpenCode `request_id`
- `nativeSessionId` (`String?`) — OpenCode `ses_*` when present on the event

Normalizer:

- Claude-family AskUserQuestion `PreToolUse`: parse questions; set `askRequestId` from tool use id if available.
- OpenCode `question.asked`: parse top-level `questions`; set `askRequestId` from `request_id` / `id`; set `nativeSessionId` from payload `session_id` / `sessionID` when present.
- OpenCode `question.reply_failed`: map to a dedicated attention signal (not a generic working pulse). Payload must include `request_id` (required). Normalizer emits an event the cubit recognizes as “restore ask waiting for this requestId” (see reconciliation). Optional `message` string for UI error copy.

### Card policy

`shouldShowAskUserQuestionCard` (pure, unit-tested):

- Requires `supportsInChatAnswer`.
- Requires non-empty structured `questions`.
- If any question is `multiSelect` **or** `questions.length > 1`: require `supportsMultiSelectInChat`; else false → banner.
- Single single-select: require non-empty options.
- Missing `askRequestId` when `answerKind == pluginSdkReply`: false → banner (cannot reply safely).

Banner widget only calls this policy; no CLI switches in UI.

**OpenCode multi UI (locked):** one card listing all questions on a single page. Each question is radio (single) or checkbox group (multi). One primary **Submit** sends `answers: List<List<String>>` in question order (selected labels per question; empty array only if the CLI schema allows skipping — otherwise require ≥1 selection per question). No per-question wizard.

### OpenCode pending reply protocol

**Store** (`AskUserAnswerPendingStore`): keyed by TeamPilot `sessionId` + member seat id + `requestId`.

Entry shape:

```text
{ requestId, answers: List<List<String>>?, reject: bool }
```

- `put` overwrites same key (retry / double-tap).
- `take` is get-once (consume on read) to prevent replay.
- Clear all entries for a seat on session dispose / seat disconnect.

**HTTP** on `TeammateBusMcpGateway` (same loopback + remote HTTP tunnel as `/agent-status` / `/idle`):

- `GET /ask-user-answer` with `X-Session` / `X-Member` (and bus token when required).
- No pending → `204`.
- Pending → `200` JSON body of the entry, then delete.

**Query:** plugin **must** poll with `?request_id=<id>`. Gateway returns that entry or 204. Omitting `request_id` is unsupported for production pollers (tests may cover 204 for empty seat).

**Plugin** (`opencode_agent_status_plugin.dart`):

On `question.asked`:

1. POST status payload including `questions`, `request_id`, `session_id`.
2. Start short-interval poll of `GET /ask-user-answer?request_id=…` until answer, reject, or timeout (align with attention TTL, default 30m, or a shorter dedicated poll deadline documented in code).
3. Call `client.question.reply` with `{ path: { sessionID, requestID }, body: { answers } }` or `client.question.reject` when available.
4. On SDK failure: POST `question.reply_failed` with `request_id` (and optional `message`) so Dart can restore waiting.
5. On success: rely on existing idle / done signals for reconciliation; Dart already moved the seat to `working` optimistically.
6. On `question.reply_failed` apply: cubit **merges** — restore `waiting` using retained ask payload; do **not** overwrite `lastEvent.askUserQuestions` with an empty/thin failure event.

**Cancel from Chat (OpenCode):** put `{ reject: true }` — do **not** send Esc to the PTY.

**Cancel from Chat (PTY family):** existing Esc inject via pty port.

### Optimistic dismiss and reconciliation

- **Success definition:**
  - `ptyPicker`: PTY write path completed (shell connected; keystrokes sent).
  - `pluginSdkReply`: pending entry successfully stored.
- On success (locked): set seat attention to **`working`**, and **retain** `lastEvent` (questions + `askRequestId`) so compose unlocks but `reply_failed` can restore. Also record the dismissed `askRequestId` on the seat entry (or a small side map) until a non-matching ask arrives or the seat is cleared.
- If a later waiting event arrives with the **same** `askRequestId`, ignore.
- If `question.reply_failed` arrives for that `askRequestId`, set attention back to **`waiting`** using the retained `lastEvent` payload; show error UI from optional `message`.
- Card `_answering` remains a local double-submit guard; it does not replace attention state.

### UX copy and errors

- Title: generic (e.g. “Agent is asking you a question” / 「正在向你提问」) — not Claude-branded. Optional later interpolation with CLI/display name is allowed but not required for v1 of this design.
- Failure: snackbar or inline error on the card (“Couldn’t send answer”, terminal disconnected, reply failed). Keep card / restore waiting so the user can retry or “Answer in terminal”.
- Compose lock and history-continue block while `permissionWaiting` unchanged.

### Answer facade

Replace the Claude-only `AskUserQuestionAnswerService` with a small facade used by `ChatCubit`:

- Resolve seat CLI → capability → port.
- Inputs: sessionId, memberId, shell, questions/requestId, selected labels or option index, cancel flag.
- Return a result type (`ok` / `failed(reason)`) so UI can show errors and cubit can decide whether to clear waiting.

PTY port keeps the 120ms digit→Enter gap and Esc cancel behavior covered by existing unit tests (migrated).

## Error handling summary

| Case | Behavior |
|------|----------|
| Shell disconnected (PTY) | Fail; keep waiting; error copy |
| Missing requestId (OpenCode) | Do not show in-chat card; banner only |
| Pending poll timeout | Plugin stops; if user already answered, `reply_failed` or timeout signal restores/keeps recoverable UI |
| SDK reply throws | `question.reply_failed` → restore waiting + error |
| Double tap | Card `_answering` + pending overwrite same requestId |
| Session/seat gone | Drop pending for seat |
| SSH remote member | `/ask-user-answer` uses the same HTTP tunnel as `/agent-status` |

## Testing

Required coverage:

- Capability matrix per CLI.
- `shouldShowAskUserQuestionCard` cases (single, multi, missing requestId, Cursor).
- PTY port digit + Esc (migrate existing).
- Pending store put / take-once / reject / seat isolation.
- Gateway `GET /ask-user-answer` 204 / 200-then-delete.
- Normalizer preserves `request_id` / `session_id`.
- Attention optimistic clear; ignore same-requestId late waiting; `reply_failed` restore.
- OpenCode plugin source string contains poll path + reply/reject.
- ChatCubit/facade dispatches by CLI; failure does not clear waiting.

## File map (expected)

| Path | Role |
|------|------|
| `client/lib/services/cli/registry/capabilities/ask_user_question_capability.dart` | Capability + per-CLI impls |
| `client/lib/services/cli/registry/tools/*_cli_tool.dart` | Register capability |
| `client/lib/services/terminal/ask_user_question_answer_service.dart` | Facade + PTY port |
| `client/lib/services/agent_status/ask_user_answer_pending_store.dart` | OpenCode pending |
| `client/lib/services/agent_status/ask_user_question_policy.dart` | Card policy |
| `agent_status_event.dart` / `agent_status_normalizer.dart` / `agent_attention_cubit.dart` | requestId, clear, reply_failed |
| `teammate_bus_mcp_gateway.dart` (+ handler wiring) | `GET /ask-user-answer` |
| `opencode_agent_status_plugin.dart` | Poll + SDK reply/reject |
| `ask_user_question_card.dart` / `agent_permission_attention_banner.dart` | Policy-driven UI; OpenCode multi UI |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | Generic title + errors |
| Matching tests under `client/test/...` | As listed above |

## Decisions locked

1. Approach A: registry capability + answer ports (not cli switches in the answer service core).
2. OpenCode uses plugin SDK reply via Bus pending store — not Dart→serve HTTP.
3. Optimistic dismiss on local handoff success → attention `working` while retaining `lastEvent` + dismissed requestId; reconcile `reply_failed` back to `waiting`.
4. Generic ask title copy.
5. OpenCode multi-select/multi-question in chat (single-page card + one Submit); PTY-family multi → banner.
6. Plugin always polls `/ask-user-answer?request_id=…`.
7. `question.reply_failed` is a first-class normalizer event with required `request_id`.
