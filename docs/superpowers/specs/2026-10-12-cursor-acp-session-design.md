# Cursor ACP Session Design

## Goal

Add a complete Agent Client Protocol (ACP) path for **personal Cursor CLI
sessions**, behind one settings switch, without replacing the existing PTY
Cursor product (team, plugins, hooks, Official login, terminal view).

Gemini remains ACP-only. Claude remains personal-ACP-by-settings. Cursor
joins that same personal-ACP-by-settings shape. A Cursor session that opts
into ACP uses the existing `AcpSessionRuntime` / chat / permission-card
stack, plus Cursor's documented client extension methods.

Decisions locked with the user (2026-10-12):

- Keep PTY Cursor. Do not replace it.
- One configuration: new personal Cursor sessions default to ACP chat
  (`cursorPersonalAcpDefault`, default `true`).
- Do this in **one implementation**: launch, `cursor_login` authenticate,
  MCP via isolated home, permission cards, and all five Cursor extension
  methods. Do not ship a stub that ignores blocking methods.
- Team sessions never use ACP in this phase.
- Desktop-local only. Android / SSH exec stay out of scope (no
  `SshExecTransport` yet).
- Protocol stack stays vendored `acpd` + `AcpProcessTransport`.
- History stays the client-owned `acp-transcript.jsonl` message document.
  Do **not** call Cursor `session/load`.

## Why native ACP (no adapter)

Cursor CLI speaks ACP on the same binary TeamPilot already launches:

```
PTY:  TeamPilot --PTY--> cursor-agent
ACP:  TeamPilot --ACP stdio--> cursor-agent acp
```

Official docs: `agent acp` over stdio, NDJSON JSON-RPC 2.0. TeamPilot's
executable name is `cursor-agent` (`CursorExecutableCapability`). Argv is
`[cursor-agent, acp]`, not `--acp` and not a second npm adapter.

```
Typical flow:
  initialize
  authenticate { methodId: "cursor_login" }
  session/new
  session/prompt
  session/update… / session/request_permission
  cursor/ask_question | cursor/create_plan   (blocking; client must reply)
  cursor/update_todos | cursor/task | cursor/generate_image  (notifications)
  session/cancel (optional)
```

## Layering

Mechanism vs declaration stays as in the Gemini spec
(`docs/superpowers/specs/2026-09-12-acp-gemini-session-design.md`) and the
Claude spec (`docs/superpowers/specs/2026-10-09-claude-acp-session-design.md`).

| Piece | Owner |
|-------|--------|
| `services/acp/*` | Protocol mechanics. Handshake gains optional `authenticate`. Client extension requests/notifications become a CLI-agnostic session seam. |
| `isAcpChatSession` | Unchanged: `session.isSimple && session.acp`. |
| `AcpCapability` | Gains optional `authenticateMethodId`. Cursor sets `"cursor_login"`; Gemini and Claude stay `null`. |
| `CursorAcpCapability` | `services/cli/cursor/capabilities/acp.dart` — argv, env, translator, extensions. |
| `CursorCliTool` | Registers `AcpCapability`. Presence does **not** mean every Cursor session is ACP. |
| Settings default | `SessionPreferences.cursorPersonalAcpDefault` (true). |
| Session fact | `AppSession.acp`. Reconnect trusts this, not the preference. |
| Launch gate | `resolveLaunchAcp` allows personal Claude **or** personal Cursor on desktop. |

No new `CliTool.cursorAcp`.

Do not add `if (cli == cursor)` in `SessionConnectExecutor`,
`AcpSessionRuntime`, or `AcpChatRuntimeCubit`. Quirks live on the
capability / translator.

## Session model

### Preference vs session

| Store | Role |
|-------|------|
| `SessionPreferences.cursorPersonalAcpDefault` | Default for **new** personal Cursor launches. Default `true`. Missing JSON key → `true`. |
| `AppSession.acp` | Durable fact for this session. Reconnect / open-existing uses it. |

Changing the preference does not rewrite existing sessions. A Cursor
session created before this feature has `acp: false` (or omitted) and
stays PTY.

Claude's `claudePersonalAcpDefault` is independent. Landing compose must
read the preference for the **selected** CLI, not always Claude's switch.

### `resolveLaunchAcp`

Today this is true only for personal Claude + `requested` + desktop.
Extend the allow-list to `CliTool.claude` **or** `CliTool.cursor`. Team,
Android, Gemini, Codex, OpenCode, FlashskyAI stay false here. Gemini ACP
is still inferred at session create, not through this helper.

`createSession` still forces `acp = false` when `sessionTeam` is
non-empty.

## Launch

`SessionConnectExecutor` already branches on `isAcpChatSession` before
member/shell connect. Cursor ACP rides that branch once `AppSession.acp`
is true.

### Argv

```
agentExecutable(cliExecutable) => cliExecutable
launchArgCandidates(executable) => [[executable, 'acp']]
```

`flagCandidates` on the translator is unused for probing (the subcommand
is not a flag). Do not probe `--acp` / `--experimental-acp`.

`cursor-agent` missing → existing executable-not-found / install path,
same as PTY. No extra adapter installer.

### Environment

ACP connect already runs `prepareSimpleConnect` and passes that env as
`baseEnv` (`prepareAcpLaunchEnvironment`). Cursor PTY simple launch
already isolates `$HOME`, pins `CURSOR_CONFIG_DIR`, writes `auth.json`,
and materializes MCP / skills / hooks into that home.

`CursorAcpCapability.buildEnvironment` **preserves `baseEnv`**. It must
not replace `HOME` with `sessionToolDir`. Cursor auth is HOME-anchored
(`auth.json` under `$HOME/.cursor`, `$XDG_CONFIG_HOME/cursor`, or
`%APPDATA%\Cursor`); `CURSOR_CONFIG_DIR` alone does not relocate it.

Production `baseEnv` always carries Cursor isolation from
`prepareSimpleConnect`. Tests inject `HOME` / `CURSOR_CONFIG_DIR` in
`baseEnv`. The capability does not invent a member-home path from
`sessionToolDir`. If those keys are absent, pass `baseEnv` through
unchanged.

Do not set `CURSOR_API_KEY` when Official login files are present (file
auth is enough). If the selected provider is key-based and PTY already
injects a key env, keep that entry from `baseEnv`.

### Authenticate

After a successful `initialize`, if `AcpCapability.authenticateMethodId`
is non-null, send `authenticate` with that `methodId`.

- Cursor: `"cursor_login"`. Pre-auth is the isolated home / API key from
  `baseEnv`; this call tells the agent to use it.
- Gemini / Claude: `null`. Do not send `authenticate` (they do not
  advertise `cursor_login`; sending it would be a handshake error).

Authenticate failure is a launch failure (`AcpChatErrorKind.launchFailed`
/ not-logged-in copy), not `AcpFlagRejected`. Do not try another argv
candidate.

Add `authenticateMethodId` to `AcpLaunchPlan` so the spawner stays
CLI-agnostic.

### Failure policy

Spawn, handshake, or authenticate failure → l10n error on the session.
**Do not** fall back to PTY for the same connect. Mixed runtime on one
session is forbidden.

## Cursor client extensions

Blocking methods hang the agent until the client replies. Shipping ACP
without them is incomplete.

Declare them on the translator (per-agent), register them in
`AcpAgentSession` (mechanics). Extract registration + parse + JSON-RPC
result encoding into `services/acp/acp_client_extensions.dart` so
`acp_session.dart` (already ~568 lines) does not grow past the service
soft limit.

### Blocking (must reply)

| Method | UI | Reply |
|--------|----|--------|
| `cursor/ask_question` | Existing `AiAskUserQuestionCard`. Parse params with `parseQuestionsList` (already accepts Cursor `prompt` / `title` / `allow_multiple`). | `{ outcome: "answered", answers: [...] }` / `{ outcome: "skipped" }` / `{ outcome: "cancelled" }` |
| `cursor/create_plan` | Existing `AiExitPlanModeCard` with `plan` as `planText`. `onOpenTerminal` cancels the turn (ACP has no terminal). `planFilePath` / `onOpenPlanFile` unused unless the request includes a path. | `{ outcome: "accepted" }` / `{ outcome: "rejected", reason? }` / `{ outcome: "cancelled" }` |

Single interactive hold: extend the existing permission `SeatHoldGate` so
permission, ask, and plan share **one** slot. A second blocking request
while one is held waits behind the gate (same as stacked permission
requests). Cubit state is a sealed `AcpPendingClientRequest`
(permission / ask / plan), not three independent nullables that can
fight in the compose slot.

`SessionChatComposeSection` today shows `AcpPermissionCard` **or** the
PTY attention banner. For ACP, switch on `AcpPendingClientRequest` and
render permission / ask / plan cards. Ask and plan cards already live in
`ai_message_ui`; wrap them in small `pages/chat/acp_*_card.dart` hosts
that call cubit reply methods (same pattern as `AcpPermissionCard`).

User cancel / `cancelTurn`: `session/cancel` **and** complete any held
blocking request with `{ outcome: "cancelled" }`.

### Notifications (no reply)

| Method | Fold into chat |
|--------|----------------|
| `cursor/update_todos` | `AiTodoListTarget` on the in-flight assistant message (`merge` honored). Persist on the next committed save. |
| `cursor/task` | Tool / subagent part (`description`, `subagentType`). |
| `cursor/generate_image` | Image part from `filePath` when present; otherwise a completed tool part with `description`. Do not block the turn waiting for bytes. |

The translator registers only the five documented Cursor methods.
Anything else stays unregistered and gets acpd's method-not-found.
Never leave a **registered** blocking request unanswered.

## History

Unchanged from `docs/superpowers/specs/2026-10-10-acp-history-message-document-design.md`.
The cubit owns `acp-transcript.jsonl`. Reopen hydrates that document.
Each connect is `session/new`.

Do not persist Cursor's ACP `sessionId` for `session/load`. Cursor has
advertised `loadSession` while returning invalid params; TeamPilot
history does not need it.

## UI

### Settings

On the Cursor row in `pages/config/cli_config_section.dart`, a switch
mirroring Claude: "Personal sessions use ACP chat" bound to
`cursorPersonalAcpDefault`.

Disabled on Android with the existing ACP-desktop-only copy (shared l10n
is fine; do not invent a second Android explanation).

No adapter install button (unlike Claude).

Extract a parameterized settings row if copying `ClaudePersonalAcpSettingsRow`
would duplicate the widget; do not scatter a third `if (cli == …)` block
beyond the existing per-CLI extra-row switch in `_buildCliRow`.

### Landing / personal compose

Landing does **not** grow a second visible switch. Create writes
`AppSession.acp` from `resolveLaunchAcp` + the selected CLI's preference
(`readPersonalAcpDefault(context, cli)`).

Fix today's bug-shaped coupling: `_currentDraft` always passes
`readClaudePersonalAcpDefault`. After this change, selecting Cursor with
Claude's switch off must not force Cursor PTY.

Gemini compose stays ACP-only. Team compose has no Cursor ACP control.

### Session chrome

ACP Cursor sessions use the existing ACP chat center (no live-terminal
toggle), same as Gemini/Claude (`isAcpChatSession` already gates this).

## File size / placement

| File | Rule |
|------|------|
| `AcpChatRuntimeCubit` (~714 lines) | Do not add extension folding inline. Extract a helper (e.g. `acp_chat_extension_fold.dart`) or keep reply methods thin and delegate. |
| `acp_session.dart` (~568 lines) | Extension registration lives in `acp_client_extensions.dart`. |
| `cli_config_section.dart` (~292 lines) | Shared settings row + one extra `_buildCliRow` branch for Cursor is enough. |
| `services/cli/cursor/capabilities/acp.dart` | New file. Capability + translator + extension method list. |

l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only.

## Error handling

| Failure | Handling |
|---------|----------|
| `cursor-agent` missing | Existing CLI install / not-found copy; session ended. |
| `acp` subcommand rejected (old CLI) | `AcpFlagRejected` then `AcpLaunchException` / `launchFailedVersion`. Replace the Gemini-hardcoded `acpLaunchFailedVersion` copy with CLI-agnostic wording so Cursor does not show "Gemini CLI". |
| `authenticate` fails / not logged in | Launch failed; reuse or add Cursor-flavored not-logged-in copy (settings → providers). |
| Handshake timeout | Frame log; launch failed. Do not probe another argv. |
| Agent crash | Inline system message + `processExited`. |
| User cancel | `session/cancel` + cancelled outcomes for held extensions. |
| Unanswered blocking extension | Forbidden. Gate timeout uses the existing 24h permission timeout, then `{ outcome: "cancelled" }`. |

## Out of scope

- `SshExecTransport` / Android ACP
- Team roster / TeamBus ACP members
- Replacing PTY Cursor
- `session/load` / persisting Cursor ACP session ids
- Advertising `fs/*` / `terminal/*` client capabilities (stay false)
- Passing `mcpServers` in `session/new` (stay `[]`; Cursor ACP uses
  isolated `.cursor/mcp.json`)
- Session mode switching UI (`agent` / `plan` / `ask`)
- Codex / OpenCode ACP
- Cursor dashboard team-level MCP (unsupported in ACP per Cursor docs)

## Testing

Constructor-injected fakes; cubit tests that need a home plane use
`setUpTestAppStorage()` / `tearDownTestAppStorage()`.

| Layer | Cases |
|-------|--------|
| `CursorAcpCapability` | argv is `[executable, 'acp']`; `agentExecutable` is the CLI binary; `buildEnvironment` keeps `HOME` / `CURSOR_CONFIG_DIR` from `baseEnv`; `authenticateMethodId` is `cursor_login`. |
| `AcpCapability` Gemini/Claude | `authenticateMethodId` is null; handshake tests still skip `authenticate`. |
| Handshake | Fake agent that requires `authenticate` before `session/new` succeeds for Cursor and fails if authenticate is skipped; Gemini fake still works with initialize-only. |
| Preferences | `cursorPersonalAcpDefault` defaults true, JSON round-trip, cubit setter. |
| `resolveLaunchAcp` | personal Cursor + requested + desktop → true; team / Android / other CLIs → false; Claude cases unchanged. |
| Landing draft | Cursor uses Cursor preference, not Claude's. |
| Connect executor | `acp` Cursor attaches ACP runtime and does not open a PTY; `acp` false Cursor still takes the shell path. |
| Extensions | `ask_question` → answered / skipped / cancelled JSON; `create_plan` → accepted / rejected / cancelled; cancelTurn cancels a held ask; `update_todos` merge vs replace; unknown blocking method does not hang (cancelled). |
| Compose | ACP pending ask/plan render instead of only the permission card. |

No live `cursor-agent acp` in CI. Manual desktop check: personal Cursor
with the switch on → ACP chat, login, permission, ask_question, plan
card, MCP tool from isolated `.cursor/mcp.json`; switch off → new
session still gets a terminal; existing PTY Cursor sessions unchanged.

## Logging

Reuse `AcpFrameLogger`. Redact `CURSOR_API_KEY` / `CURSOR_AUTH_TOKEN` if
those frames appear. Isolated `auth.json` contents must never land in
the frame log.
