# Unified Chat surface

## Goal

Replace the separate **compose landing** and **history review** product surfaces with one primary **Chat** workbench view. Terminal remains a secondary view. Sending from Chat (new conversation or continue) stays on Chat by default.

No backward compatibility: rename enums, prefs, overlays, and UI copy; do not keep aliases or migrate old preference keys.

## Product model

Workspace center pane has two workbench views:

| View | Role |
|------|------|
| **Chat** | Primary conversation surface (default) |
| **Terminal** | Embedded PTY (advanced) |

Chat has two content states of the same shell:

| State | When | Body |
|-------|------|------|
| **Unbound** | New-chat mode (`newChatActive`) — no session selected for the center pane | Launch chrome (project / worktree / team·expert / permissions / presets) + bottom compose; empty or light empty-state |
| **Bound** | A session tab is focused | Transcript + bottom continue compose; session-scoped chrome |

After submit from either state, **default stays on Chat**. Terminal only if the user toggles or enables the preference below.

## Architecture

### Rename (breaking)

| Before | After |
|--------|--------|
| `SessionWorkbenchView.history` | `SessionWorkbenchView.chat` |
| `ChatWorkbenchOverlay.history` | `ChatWorkbenchOverlay.chat` |
| `composeActive` / `enterComposeMode` (product-facing names) | `newChatActive` / `enterNewChat` (internal API renamed to match) |
| UI copy "History" (workbench toggle) | "Chat" |
| `historySubmitSwitchesToTerminal` | **removed** |

### Preference

| Key | Default | Behavior |
|-----|---------|----------|
| `chatSubmitSwitchesToTerminal` | `false` | When `true`, Chat submit (unbound create+send **or** bound continue) switches workbench to Terminal. When `false`, keep Chat (`preserveWorkbenchView: true` on open/connect). |
| `openExistingSessionStartsTerminal` | `false` (unchanged) | Sidebar / deep-link open of an **existing** session: connect + Terminal when on; Chat review when off. |

Settings UI: one row for `chatSubmitSwitchesToTerminal` next to the existing open-existing terminal toggle. Do not keep a separate landing-only or history-only switch.

### UI shell

- Introduce **`WorkspaceChatPane`** (name may be adjusted in plan) as the center-pane Chat shell.
- It replaces `WorkspaceComposeLandingPane` + `SessionHistoryReview` as the product entry for Chat content.
- Shared: bottom compose pipeline, workbench chrome patterns, submit stay-on-Chat gate.
- Branched: unbound launch chrome vs bound transcript/live refresh.
- Existing landing draft / prefs stores and history transcript loaders remain; they become backends for the two Chat states, not separate pages.

Workbench toggle: Chat ↔ Terminal (icons/tooltips updated).

### Launch / submit flow

**Unbound submit (new conversation):**

1. Persist landing draft as today.
2. `requestCreateAndOpenSession` with `preserveWorkbenchView: !chatSubmitSwitchesToTerminal` (thread through `SessionCreateRequest` → `SessionOpenRequest`).
3. Connect, deliver prompt, apply first-prompt title.
4. If preference off: leave `SessionWorkbenchView.chat` (do not force Terminal in `SessionTabSurfaceCoordinator`).
5. If preference on: set Terminal (current create behavior).

**Bound submit (continue):**

1. Same gate as today’s history continue, but read `chatSubmitSwitchesToTerminal`.
2. `preserveWorkbenchView: !chatSubmitSwitchesToTerminal`.
3. Live transcript refresh while PTY runs offstage when staying on Chat.

**Create without message** (sidebar new chat / worktree helpers that only open a session): still create+connect as today; default workbench view is Chat unless a future plan changes that path. This spec’s submit preference applies only to **Chat submit** (message send), not silent create.

### Automations / internal materialize

No change to automation connect semantics or headless materialize. Workbench view for non-interactive opens is out of scope; do not force Chat for automations.

## Non-goals

- Preference key migration or reading `historySubmitSwitchesToTerminal`
- Enum/API aliases for `history` / `composeActive`
- Embedding Terminal inside message bubbles
- TeamBus / multi-member layout redesign
- Automation dispatcher behavior changes

## Testing

- Unbound submit → create, deliver, stay on Chat when preference false
- Bound continue → connect, deliver, stay on Chat when preference false
- Preference true → both submit paths switch to Terminal
- Open existing session still respects `openExistingSessionStartsTerminal`
- Rename sweep: unit tests, keys, l10n for workbench toggle and settings row
- Overlay: Chat stays mounted during continue connect (same rule as former History overlay)

## Implementation notes

- `ChatTab.workbenchView` default: `SessionWorkbenchView.chat`
- `resolveChatWorkbenchOverlay`: Chat view keeps Chat overlay during `sessionConnectInProgress` (do not swap to full-screen session-starting spinner)
- Gate helper: e.g. `shouldSwitchToTerminalAfterChatSubmit(bool chatSubmitSwitchesToTerminal)` replacing the history-named helper
- Side-effect call sites that hardcode `SessionWorkbenchView.terminal` after landing submit must go through the preference gate
