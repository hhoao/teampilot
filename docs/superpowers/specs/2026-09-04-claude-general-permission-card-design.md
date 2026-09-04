# Claude Family General Permission Card — Design

**Date:** 2026-09-04
**Status:** Approved (brainstorming complete)

## Problem

Claude Code (and family: flashskyai, codex) permission requests are already
visible to TeamPilot — the injected `PermissionRequest` HTTP hook fires with
`tool_name` / `tool_input` and the seat enters `waiting` — but the gateway
answers `{}` immediately, so the native TUI prompt opens inside the embedded
terminal. The chat only shows a generic attention banner ("jump to terminal").
Only `AskUserQuestion` and `ExitPlanMode` get interactive chat cards today.

Official Claude Code `PermissionRequest` decision control lets a hook reply
with a `decision` object (`behavior: allow|deny`, plus `updatedPermissions` to
persist rules). TeamPilot already uses this path for `ExitPlanMode` via
`ExitPlanPermissionRequestGate`; this design generalizes it to every tool.

## Goals

- A general tool permission request renders `AiPermissionCard` in chat with
  Allow / Always allow / Deny / Answer in terminal, for the whole Claude family
  (claude, flashskyai, codex).
- "Always allow" reuses Claude's own `permission_suggestions` — echoed back as
  `updatedPermissions`, identical semantics to the native dialog.
- Answering in the terminal remains possible: releasing the hold makes the
  gateway answer `{}` so the native TUI prompt appears.
- Zero behavior change to the shipped ExitPlanMode / AskUserQuestion paths.

## Non-goals

- Custom rule-builder UI (no hand-authored permission rules; only official
  suggestion echo).
- Cursor (no `PermissionRequest` event) and OpenCode changes (SDK path stays).
- `interrupt: true` on deny (deny + message matches the native esc semantics).

## Architecture

```
Claude Code ──POST PermissionRequest──▶ AgentEventGateway (journal → publish)
                                          │
                    ┌─────────────────────┼──────────────────────────┐
                    ▼                     ▼                          ▼
        AskUserQuestion          ExitPlanMode                GeneralPermission
        Projection (现状)        Projection (现状)           Projection (new)
        AskUserQuestionHookGate  ExitPlan*Gates (现状)       GeneralPermissionRequestGate (new)
                                                                              │
                     AttentionCubit ◀── waiting + AgentPermissionRequest ◀───┘
                              │
                    AiPermissionCard (reused, small API change)
                              │ Allow / Always / Deny / Answer in terminal
                    ChatCubit.answerPermissionRequest (per-interaction routing)
                              │
                    gate.complete → decision JSON → HTTP response → Claude Code
```

Approach: **independent gate per interactive concern, over a shared hold
primitive**. The ExitPlan gates are not generalized in place — their shipped
plan-fingerprint memory stays untouched.

## New Components

### `SeatHoldGate<TReply>` (`services/agent_status/seat_hold_gate.dart`)

Generic single-slot seat-keyed hold primitive, extracted from
`ExitPlanPermissionRequestGate` mechanics:

- `wait({sessionId, memberId, timeout})` → `Future<TReply?>` — `null` on
  timeout (gateway falls through to `{}`); a second `wait` on the same seat
  resolves the previous completer with the gate's default stale reply.
- `complete({sessionId, memberId, reply})` → `bool`
- `hasWaiter({sessionId, memberId})` → `bool`
- `releaseHold({sessionId, memberId})` → `bool` — active fall-through: the
  held `wait` resolves `null`, gateway answers `{}`, native TUI takes over.
- `clearSeat` / `clearSession` — complete all held waiters with the
  caller-supplied default reply (deny semantics for permissions).

`ExitPlanPermissionRequestGate` is refactored to this primitive plus its
plan-fingerprint `remember`/`forget` memory — **zero behavior change**,
guarded by the existing test suite.

### `GeneralPermissionRequestGate`

A `SeatHoldGate<GeneralPermissionRequestReply>`. The gate holds only the
reply future — the echo payload (`permission_suggestions`) travels through
`AgentPermissionRequest` in attention state, and the card callback carries
the selected option's `payload` up to `ChatCubit`, which builds the reply.
No duplicate payload storage in the gate.

### `GeneralPermissionRequestReply`

```dart
class GeneralPermissionRequestReply {
  final bool allow;                    // deny otherwise
  final List<Map<String, Object?>> updatedPermissions; // echoed suggestions (allow + always)
  final String? denyMessage;           // 'User denied via TeamPilot'
}
```

Hook response (official schema, mirrors `ExitPlanPermissionRequestReply`):

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedPermissions": [ /* echoed suggestion entry */ ]
    }
  }
}
```

### `GeneralPermissionRuntimeEventProjection`

Responder projection in `runtime_event_projection.dart`. Routing guard is
strictly complementary to `ExitPlanModeRuntimeEventProjection`:

- `hook_event_name == 'PermissionRequest'` AND `isExitPlanModeTool(tool_name)`
  → existing plan gates (unchanged).
- `PermissionRequest` AND **not** ExitPlanMode AND
  `capability.supportsInChatPermissionReply` → general gate hold.

The two projections never hold the same event (source-level mutual exclusion:
the normalizer only builds a general `permissionRequest` payload for
non-ExitPlanMode tools, and the projection skips ExitPlanMode tools).

## Data Model: Unified Always Options

`AgentPermissionRequest.always: List<String>` is generalized to structured
options:

```dart
class AgentPermissionAlwaysOption {
  final String label;   // UI text, e.g. "Always allow Bash(rm -rf node_modules)"
  final Object? payload; // opaque: OpenCode = prefix string; Claude = raw suggestion entry
}
```

- **OpenCode** normalizer maps its prefixes to options with string payloads;
  its reply path (`once|always|reject` via plugin SDK pending store) is
  unchanged.
- **Claude family normalizer** (`ClaudeFamilyAgentStatusNormalizer`) builds
  `AgentPermissionRequest` on `PermissionRequest` events:
  - `description` = `tool_name` + `tool_input` preview (reuse
    `deriveToolInputPreview`)
  - always options = `permission_suggestions` entries (human label + raw JSON
    payload)
  - **ExitPlanMode tools are excluded** — they must render the plan card.
- `AiPermissionCard.onReply` generalizes from a string to (reply kind +
  selected option).

Implementation note (accepted deviation): the card now re-enables its
buttons after a successful reply (previously permanently disabled). This
enables multi-option always flows on stale attention entries; in-flight taps
stay guarded by the answering latch and `markAskAnswered` dismisses the card
synchronously on success, so the double-answer window is negligible.

### Policy gating (`shouldShowPermissionCard`)

The current policy rejects cards when `askRequestId` is empty. That
correlation id only exists for the plugin-SDK channel (OpenCode). The check
becomes channel-conditional: request id required for `pluginSdkReply`, not
required for the hook-hold channel (correlation is the gate's seat key).

## Answer Routing

`ChatCubit.answerPermissionRequest` routes per interaction kind:

| CLI | Channel | Mechanism |
|-----|---------|-----------|
| OpenCode | `AskUserAnswerKind.pluginSdkReply` (unchanged) | pending store |
| Claude family | `hookHold` (new) | `gate.complete`; allow + always echoes `updatedPermissions` |

New `ChatCubit.releasePermissionToTerminal`: the card's "answer in terminal"
button calls `gate.releaseHold`, the gateway answers `{}`, and the native TUI
prompt appears for terminal-side selection.

**Deny semantics:** `behavior: 'deny'` + message, no `interrupt` (matches the
native dialog's esc: Claude receives the reason and adapts).

## Capability & Lifecycle

- `ClaudeChatInteraction` / flashskyai / codex:
  `supportsInChatPermissionReply => true` (whole family). `answerKind`
  unchanged.
- Gate lifecycle follows the existing gate precedent (shipped
  `ExitPlanPermissionRequestGate`): no explicit session-end clearing in
  production; held waiters self-remove via deny-on-replace (a newer request on
  the same seat) or the 24h timeout, and the CLI process ending closes the
  HTTP connection anyway. The gate exposes `clearSeat` / `clearSession` for
  future lifecycle wiring if it ever becomes necessary.
- Hook injection, 1-day entry timeout, `{}` immediate answers for unheld
  events — all current behavior, no changes.
- `permission_sticky` already covers general-permission waiting stickiness
  and approved-tool-resume clearing; a successful answer calls
  `markAskAnswered` to settle attention.

## Degradation & Boundaries

- Older Claude Code without `decision` control: gateway answers `{}` as today
  → native TUI. Safe degradation.
- `allow` cannot override an explicit deny rule (official semantics); sandbox
  network requests never fire `PermissionRequest` (notification
  `permission_prompt` only — out of scope).
- Headless subagents: official semantics deny when nothing answers; the held
  hook + card makes approval possible where the TUI could never show — a gain.

## Testing

Following existing patterns (`exit_plan_mode_hook_gate_test`,
`agent_status_http_handler_exit_plan_test`):

1. `SeatHoldGate` primitive unit tests (wait/complete/releaseHold/clear,
   stale-waiter replacement).
2. `GeneralPermissionRequestGate` tests (suggestion echo via card-callback
   payload, releaseHold).
3. Projection routing mutual exclusion (ExitPlanMode vs general, all three
   family CLIs; non-supporting CLIs never held).
4. Normalizer tests (suggestions parsing, ExitPlanMode exclusion).
5. Banner widget tests (card rendering, button callbacks, answer-in-terminal).
6. HTTP end-to-end (hold → complete → decision JSON assertion; release → `{}`).
7. `ExitPlanPermissionRequestGate` refactor regression (full existing suite).
