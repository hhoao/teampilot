# Permission-request confirmation in chat (design)

**Date:** 2026-08-07
**Status:** Approved for planning
**Scope:** Let users answer Claude-family `PermissionRequest` inline in Chat (Allow / Deny) instead of always jumping to the terminal, gated by the session's current workbench view. Generalizes the AskUserQuestion hook-hold to be view-aware (fixing the frozen-terminal / dead "answer in terminal" button), and adds a permission-request card on top.

## Problem

The chat UI already renders an interactive card for Claude-family `AskUserQuestion` (hook held open → card → answer → `updatedInput.answers`). But `PermissionRequest` — fired before every permission-gated tool call (Bash, Read, Write, WebFetch, …) — only surfaces as a generic banner: *"This agent needs confirmation in the Terminal."* + **Open Terminal**. The user must switch to the terminal and press keys in the native permission TUI.

At the same time, the AskUserQuestion hook-hold has two latent issues:

1. **Terminal freezes when unanswered.** The `PreToolUse` hook for AskUserQuestion holds the HTTP response (timeout 24h). Claude Code renders the question TUI only after the hook returns. If the card isn't answered, the terminal stays frozen at the pre-question frame for up to 24h.
2. **The "Answer in terminal" button is dead.** `_openTerminal` (`agent_permission_attention_banner.dart`) only switches the workbench view to terminal; it never releases the held hook, so the native TUI never renders.

Both issues stem from the same root: **the hook is held regardless of where the user is looking.** The fix for both is to make the hold decision view-aware, then add the permission card on top.

## Goals

1. **View-aware hook hold.** When a Claude-family `PermissionRequest` (or `AskUserQuestion` `PreToolUse`) arrives, hold the hook **only if** the session's active workbench view is Chat **and** the requesting seat is the selected one. In Terminal view (or no open tab / non-selected seat), return immediately so the native TUI renders — exactly today's terminal behavior, zero regression.
2. **Release on view switch.** If the user switches Chat → Terminal while a hook is held, release it (respond `{}`) so the native prompt appears immediately. No frozen-terminal-without-a-card state.
3. **Inline permission card.** In Chat view, render a `PermissionRequestCard` (tool name + command/path preview + **Allow** / **Deny** + answer-in-terminal) above compose; answering returns `decision.behavior: allow|deny` and skips the TUI.
4. **Fix AskUserQuestion.** Same view-aware hold for `AskUserQuestion`; `_openTerminal` releases the held hook (works for both card types). Users now answer where they are looking.
5. **Capability-gated.** New `PermissionRequestCapability` per CLI (Claude-family yes; Cursor / OpenCode no). Falls back to the generic banner otherwise.

## Non-goals

- "Always allow" (writes to `settings.json` `permissions.ask`; deferred).
- OpenCode `permission.asked` inline answer (goes through the plugin-SDK path; separate future work).
- Cursor permissions (title-path only; no `PermissionRequest` hook).
- Replacing the native TUI as a fallback; the native prompt remains the fallback whenever the card is not answerable.
- Changing `dangerouslySkipPermissions` (bypass mode never holds hooks).

## Support matrix

| CLI | PermissionRequest hook | In-chat answer | Card answer port |
|-----|------------------------|----------------|------------------|
| Claude | yes (`PermissionRequest`) | yes | `PermissionRequestHookGate` → `decision.behavior` |
| flashskyai | yes (Claude-family shape) | yes | hook gate |
| Codex | yes (`CodexAgentStatusOverlay` provisions the hook) | yes | hook gate |
| OpenCode | `permission.asked` plugin event (no hold) | no (this scope) | — |
| Cursor | no | no | — |

## Architecture

### Capability

New `PermissionRequestCapability` under `client/lib/services/cli/registry/capabilities/`:

```dart
abstract interface class PermissionRequestCapability implements CliCapability {
  bool get supportsInChatAnswer;
}

final class ClaudePermissionRequestCapability
    implements PermissionRequestCapability {
  const ClaudePermissionRequestCapability();
  @override
  bool get supportsInChatAnswer => true;
}

final class NoPermissionRequestCapability
    implements PermissionRequestCapability {
  const NoPermissionRequestCapability();
  @override
  bool get supportsInChatAnswer => false;
}
```

Wire onto `ClaudeCliToolDefinition`, `FlashskyaiCliToolDefinition`, `CodexCliToolDefinition` (true) and `Cursor` / `Opencode` (false), mirroring `AskUserQuestionCapability` registration.

### View-aware hold policy

New pure function in `services/agent_status/permission_request_policy.dart` (generalized; also used by AskUserQuestion):

```dart
/// Whether an agent-status hook that can be answered in Chat should be held
/// open (awaiting the chat card) instead of letting the native TUI render.
bool shouldHoldInChat({
  required bool chatViewActive,   // workbench view == chat AND tab open
  required bool seatSelected,     // requesting seat == selected member
  required bool skipPermissions,  // dangerouslySkipPermissions (bypass mode)
  required bool capabilitySupportsInChat,
}) {
  if (skipPermissions) return false;
  if (!chatViewActive) return false;
  if (!seatSelected) return false;
  return capabilitySupportsInChat;
}
```

Wired as a late-bound resolver `bool Function(String sessionId, String memberId) resolveHoldInChat` on the handler (populated once `ChatCubit` exists; reads `tabStore.workbenchView` + selected seat + CLI capability + seat skip). Same resolver serves AskUserQuestion and PermissionRequest.

### Hook gate

New `PermissionRequestHookGate` under `services/agent_status/permission_request_hook_gate.dart`. Keyed by `(sessionId, memberId)` — `PermissionRequest` carries no `tool_use_id` (per `claude_permission_sticky.dart`), and a single seat blocks on at most one permission at a time.

```dart
sealed class PermissionRequestHookReply {}
final class PermissionDecisionAllow extends PermissionRequestHookReply {}
final class PermissionDecisionDeny extends PermissionRequestHookReply {}
/// No decision — respond `{}`, let Claude Code show its native prompt.
final class PermissionDecisionFallthrough extends PermissionRequestHookReply {}

final class PermissionRequestHookGate {
  Future<PermissionRequestHookReply?> wait({
    required String sessionId, required String memberId,
    Duration timeout = const Duration(hours: 24),
  });
  bool complete({
    required String sessionId, required String memberId,
    required PermissionRequestHookReply reply,
  });
  bool hasWaiter({required String sessionId, required String memberId});
  /// Release every held hook for a session (view switch / teardown) with
  /// fallthrough.
  void releaseForSession(String sessionId);
  void clearSeat({required String sessionId, required String memberId});
  void clearSession(String sessionId);
}
```

A second `wait` for an already-held seat completes the prior waiter with fallthrough (defensive; should not occur while the CLI is blocked).

### HTTP handler

Extend `AgentStatusHttpHandler` (`agent_status_http_handler.dart`):

- Add optional `PermissionRequestHookGate? permissionGate` and `bool Function(String, String)? resolveHoldInChat`.
- In `handle`, after normalizing a `PermissionRequest` event: if `resolveHoldInChat` is true **and** `permissionGate` is non-null, `await permissionGate.wait(...)` and write the decision JSON; otherwise write `{}` (today's behavior).
- Response formats (Claude Code docs; note the nested `decision` object, unlike PreToolUse's flat `permissionDecision`):
  - allow → `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`
  - deny → `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}`
  - fallthrough / no hold → `{}`
- Generalize `_maybeAnswerAskUserQuestionHook` to consult `resolveHoldInChat` (do not hold AskUserQuestion when the view is terminal; respond `{}` so the native question TUI renders).

### Card

New `PermissionRequestCard` under `pages/chat/permission_request_card.dart`:

- Shows a pill (tool name, e.g. `Bash`) + the command / path preview (`event.toolInput` via `deriveToolInputPreview`).
- Buttons: **Allow** (primary), **Deny**, and a terminal icon ("answer in terminal").
- Keyboard: `Enter` = Allow, `Esc` = Deny.
- Renders in `AgentPermissionAttentionBanner` when `shouldShowPermissionRequestCard(...)` (capability + waiting entry with `hookEventName == 'PermissionRequest'`) — alongside the existing AskUserQuestion branch. Compose hidden while the card is showing (extend the existing `isSelectedSeatAskCard` logic with `isSelectedSeatPermissionCard`).

### Cubit wiring

- `ChatCubit.answerPermissionRequest({sessionId, memberId})` → `PermissionRequestHookGate.complete(allow)` → optimistic `AgentAttentionCubit.markAskAnswered` (reused) on success.
- `ChatCubit.denyPermissionRequest({sessionId, memberId})` → `complete(deny)` → optimistic dismiss.
- `ChatCubit.setSessionWorkbenchView` → when switching to Terminal, `permissionGate.releaseForSession(sessionId)` (fallthrough) so the native prompt renders immediately. Same release on tab close / session teardown (`disposeSessionBus`, `closeSession`).
- `AgentPermissionAttentionBanner._openTerminal` → **release the held hook for the seat before** switching view (fixes the dead button for both card types).

## Data flow

```
CLI permission / AskUserQuestion
  → hook POST /agent-status?event=PermissionRequest (timeout 86400)
  → AgentStatusNormalizer → waiting attention (+ toolName/toolInput)
  → AgentStatusHttpHandler
       resolveHoldInChat? → await permissionGate.wait / askGate.wait
            else → write {} (native TUI)
  → AgentPermissionAttentionBanner
       shouldShowPermissionRequestCard? → PermissionRequestCard
       shouldShowAskUserQuestionCard?   → AskUserQuestionCard
       else → generic banner (Open Terminal)
  → user Allow/Deny → ChatCubit.answer/deny → gate.complete → decision JSON → TUI skipped
  → view switch to terminal → setSessionWorkbenchView → releaseForSession → {} → native TUI
```

## Error handling & edge cases

- **Bypass mode** (`dangerouslySkipPermissions`): `shouldHoldInChat` returns false → hook never held, native auto-approval unchanged.
- **No open tab / view unknown**: resolver returns "not chat" → no hold.
- **Team session, non-selected seat requests**: resolver returns "not selected" → no hold → that member's native TUI renders (no invisible card).
- **View switch mid-hold**: release on `setSessionWorkbenchView` → fallthrough, native prompt renders.
- **24h timeout**: `wait` returns null → `{}` → native prompt (belt-and-suspenders; view-switch release is the primary path).
- **Hook gate teardown**: `clearSeat`/`clearSession` complete waiters with fallthrough, so a dying session never strands a held hook.
- **Hook corrupt / oversized**: existing handler catch → `{}` (unchanged).

## Testing

- `permission_request_policy_test.dart`: `shouldHoldInChat` truth table (view × seat × skip × capability).
- `permission_request_hook_gate_test.dart`: wait / complete / releaseForSession / clearSeat / clearSession, second-wait replace.
- `agent_status_http_handler` tests: PermissionRequest with hold → allow/deny JSON; no hold / skip / view=terminal → `{}`; AskUserQuestion view-aware hold.
- `chat_cubit` tests: `answerPermissionRequest` / `denyPermissionRequest` complete the gate and dismiss attention; `setSessionWorkbenchView` → terminal releases held hooks.
- `permission_request_card` widget test: renders preview, Allow/Deny submit the decision, keyboard shortcuts.
- l10n: add `en` + `zh` strings (card title, allow, deny, answer-in-terminal).

## Future work

- "Always allow" (write `permissions.ask` in the workspace/identity `settings.json`).
- OpenCode `permission.asked` inline answer via plugin SDK pending store.
