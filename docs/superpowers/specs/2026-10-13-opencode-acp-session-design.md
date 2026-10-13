# OpenCode ACP Session Design

## Goal

Add a complete Agent Client Protocol (ACP) path for **personal and mixed
TeamBus OpenCode sessions**, behind one settings switch, without replacing
the existing PTY OpenCode product (team, plugins, hooks, providers,
terminal view).

Gemini remains ACP-only. Claude, Cursor, and Codex remain
personal-ACP-by-settings (and seed mixed seats). OpenCode joins that same
shape. An OpenCode session or seat that opts into ACP uses the existing
`AcpSessionRuntime` / chat / permission-card / app-owned transcript stack.

Decisions locked with the user (2026-10-13):

- Keep PTY OpenCode. Do not replace it.
- Scope **A**: personal sessions **and** mixed TeamBus seats in one
  implementation. Native teams stay PTY.
- Default **A**: new personal OpenCode sessions and new mixed OpenCode
  seats default to ACP chat (`opencodePersonalAcpDefault`, default
  `true`). Missing JSON key → `true`.
- Native `opencode acp`. No npm adapter, no second binary.
- Handshake does **not** send `authenticate` / `opencode-login`.
  Credentials come from the isolated session home already staged for PTY.
- MCP is config-only for this CLI: `forwardSessionNewMcpServers = false`.
- History stays the client-owned `acp-transcript.jsonl` message document.
  Do **not** call OpenCode `session/load`.
- Desktop-local only. Android / SSH exec stay out of scope (no
  `SshExecTransport` yet).
- Protocol stack stays vendored `acpd` + `AcpProcessTransport`.
- Failure does not fall back to PTY.

This spec supersedes the mixed-team ACP spec's first-wave exclusion
("OpenCode stays PTY") in
`docs/superpowers/specs/2026-10-12-mixed-team-acp-session-design.md`.
FlashskyAI remains PTY.

## Why native ACP (no adapter)

OpenCode speaks ACP on the same binary TeamPilot already launches:

```
PTY:  TeamPilot --PTY--> opencode
ACP:  TeamPilot --ACP stdio--> opencode acp
```

Official docs (`https://opencode.ai/v2/docs/cli/acp/`): `opencode acp`
over stdio, NDJSON JSON-RPC, ACP protocol version 1. Argv is
`[opencode, acp]`, not `--acp` and not a second npm adapter. The process
starts a private OpenCode server; it does not open a network port for
ACP. One process can serve many ACP sessions; TeamPilot still uses one
process per personal session or mixed seat (existing `AcpAgentConnection`
refuses a second `session/new`).

```
Typical flow:
  initialize
  session/new
  session/prompt
  session/update… / session/request_permission
  session/cancel (optional)
```

No Cursor-style client extension methods. Standard ACP permission
options are `once` / `always` / `reject`.

## Layering

Mechanism vs declaration stays as in the Gemini spec
(`docs/superpowers/specs/2026-09-12-acp-gemini-session-design.md`), the
Claude spec (`docs/superpowers/specs/2026-10-09-claude-acp-session-design.md`),
the Cursor spec (`docs/superpowers/specs/2026-10-12-cursor-acp-session-design.md`),
and the mixed-team spec
(`docs/superpowers/specs/2026-10-12-mixed-team-acp-session-design.md`).

| Piece | Owner |
|-------|--------|
| `services/acp/*` | Unchanged protocol mechanics. Do not advertise `fs` / `terminal` / `auth.terminal` / `_meta["terminal-auth"]`. |
| `isAcpChatSession` | Unchanged: `session.isSimple && session.acp`. |
| `isAcpChatSeat` / `shouldAttachMemberAcp` | Unchanged gates: mixed + local desktop + registered `AcpCapability`. Registering OpenCode's capability is enough for attach. |
| `OpencodeAcpCapability` | `services/cli/opencode/capabilities/acp.dart` — argv, env, translator. |
| `OpencodeCliTool` | Registers `AcpCapability`. Presence does **not** mean every OpenCode session is ACP. |
| Settings default | `SessionPreferences.opencodePersonalAcpDefault` (true). |
| Personal session fact | `AppSession.acp`. Reconnect trusts this, not the preference. |
| Mixed seat fact | `SessionMemberBinding.acp`. Omit when false. |
| Launch gate | `resolveLaunchAcp` allow-list adds `CliTool.opencode`. |
| Mixed seed | `stampMemberAcp` / `SessionCreateRequest.seedOpencodeMemberAcp` from the same preference. |

No new `CliTool.opencodeAcp`.

Do not add `if (cli == opencode)` in `SessionConnectExecutor`,
`AcpSessionRuntime`, or `AcpChatRuntimeCubit`. Quirks live on the
capability / translator. Extending the existing allow-lists in
`resolveLaunchAcp`, `readPersonalAcpDefault`, `_requestedMemberAcpSeed`,
and `_buildCliRow` is the same pattern Claude / Cursor / Codex already
use; do not invent a per-CLI preference map in this phase.

## Session model

### Preference vs session vs seat

| Store | Role |
|-------|------|
| `SessionPreferences.opencodePersonalAcpDefault` | Default for **new** personal OpenCode launches and **new** mixed OpenCode seats. Default `true`. Missing JSON key → `true`. |
| `AppSession.acp` | Durable fact for a **personal** session. Reconnect / open-existing uses it. Team sessions always persist `acp: false`. |
| `SessionMemberBinding.acp` | Durable fact for a mixed seat. Reconnect uses it. |

Changing the preference does not rewrite existing sessions or seats. An
OpenCode session created before this feature has `acp: false` (or
omitted) and stays PTY.

Claude / Cursor / Codex preferences stay independent. Landing compose
already reads `readPersonalAcpDefault(context, cli)` for the selected
CLI; add the OpenCode branch there.

### `resolveLaunchAcp`

True only for personal Claude, Cursor, Codex, **or OpenCode** when
`requested` is true on desktop. Team, Android, Gemini, FlashskyAI stay
false here. Gemini ACP is still inferred at session create, not through
this helper.

`createSession` still forces `AppSession.acp = false` when
`sessionTeam` is non-empty.

### Mixed seats

`_memberAcpGates` already returns true when the CLI registers
`AcpCapability`. After OpenCode registers the capability, mixed local
desktop OpenCode seats can attach.

Seed plumbing clones Cursor:

- `SessionCreateRequest.seedOpencodeMemberAcp` (default `true`)
- `stampMemberAcp(..., seedOpencodeMemberAcp: …)`
- `_requestedMemberAcpSeed` maps `CliTool.opencode` to that seed
- Workspace / repository / coordinator call sites that already thread
  `seedCursorMemberAcp` also thread the OpenCode seed from
  `readPersonalAcpDefault(context, CliTool.opencode)`

Gemini mixed members stay forced ACP. Native teams, Android, SSH, WSL,
and Termux stay PTY.

## Launch

Personal: `SessionConnectExecutor` already branches on
`isAcpChatSession` before member/shell connect. OpenCode ACP rides that
branch once `AppSession.acp` is true.

Mixed: `shouldAttachMemberAcp` already branches per seat. OpenCode ACP
rides that branch once `SessionMemberBinding.acp` is true and the
capability is registered.

### Argv

```
agentExecutable(cliExecutable) => cliExecutable
launchArgCandidates(executable) => [[executable, 'acp']]
```

`flagCandidates` on the translator is unused (the subcommand is not a
flag). Do not probe `--acp` / `--experimental-acp`. Do not add
`--login`.

`opencode` missing → existing executable-not-found / install path, same
as PTY. No extra adapter installer.

### Environment

ACP connect already runs `prepareSimpleConnect` (personal) or
`prepareTeamConnect` (mixed) and passes that env as `baseEnv`
(`prepareAcpLaunchEnvironment` / `prepareAcpTeamLaunchEnvironment`).
OpenCode PTY launch already materializes session home and injects:

- `OPENCODE_CONFIG_DIR`
- `OPENCODE_DB`
- `OPENCODE_AUTH_CONTENT` when the selected provider needs credentials
- `OPENCODE_CLI_CONFIG_CONTENT` (`{"tabs":{"mode":"off"}}`)

`OpencodeAcpCapability.buildEnvironment` **preserves `baseEnv`**. It
must not replace `HOME` with `sessionToolDir`, and must not invent
OpenCode paths from `sessionToolDir`. If those keys are absent, pass
`baseEnv` through unchanged.

Tests inject the `OPENCODE_*` keys in `baseEnv`. Production always
carries them from session-home materialization.

Additional workspace directories stay config-only:
`permissions.external_directory` written by existing OpenCode
session-home code. This phase does **not** extend `session/new` with
`additionalDirectories`.

### Authenticate

`authenticateMethodId = null`. `resolveAuthenticateMethodId` returns
null. The spawner skips `authenticate`.

OpenCode advertises method id `opencode-login`. The official client
docs: that method does not collect credentials; if the client sets
`auth.terminal` / `_meta["terminal-auth"]`, the client must **not** send
`authenticate` and must instead relaunch with `--login`. TeamPilot
advertises neither, so the method is unused.

Credentials are the isolated-home artifacts already in `baseEnv`. If a
later prompt fails because a provider needs authentication, OpenCode
returns ACP `auth_required`. Treat that as a turn failure with the
generic `acpChatNotLoggedIn` copy. Do not send `authenticate` mid-turn.
Do not add an `if (cli == opencode)` strings branch in `app_shell.dart`
(Codex keeps its own adapter copy; OpenCode uses the shared not-logged-in
string).

### MCP

`forwardSessionNewMcpServers = false`, same as Cursor.

OpenCode reads MCP from the session directory's `opencode.json`. Staging
already writes catalog MCP and, for mixed seats, teammate-bus extra MCP
into that file. Forwarding the same HTTP servers on `session/new` would
double-register them. Cursor hit "Failed to initialize session services"
on that pattern.

When `forwardSessionNewMcpServers` is false, `AcpSessionRuntime` already
omits `mcpServers` on `session/new` and logs the count. Mixed
teammate-bus still reaches the agent through staged config from
`prepareTeamConnect`.

If a later desktop check shows mixed OpenCode ACP seats cannot see
teammate-bus, flip this flag to `true` in a follow-up; do not guess in
this phase.

### Failure policy

Spawn or handshake failure → l10n error on the session / seat.
**Do not** fall back to PTY for the same connect. Mixed runtime on one
personal session is forbidden. A mixed seat that fails ACP attach stays
failed (existing mixed-team rule).

## History

Unchanged from
`docs/superpowers/specs/2026-10-10-acp-history-message-document-design.md`.
The cubit owns `acp-transcript.jsonl`. Reopen hydrates that document.
Each connect is `session/new`.

Do not persist OpenCode's ACP `sessionId`. Do not call `session/load`,
`session/resume`, or `session/fork`. OpenCode advertises `loadSession`;
TeamPilot history does not need it. PTY OpenCode SQLite
(`OPENCODE_DB` / `AiHistoryCapability`) stays the PTY path.

Ignore these OpenCode ACP extras (do not fold, persist, or advertise
client support):

- `available_commands_update`
- `usage_update` / prompt `usage`
- `_meta["opencode/child-session"]` (child tool calls still appear as
  ordinary `session/update` tool_call entries)
- `_meta["opencode/retry"]` / `_meta["opencode/compaction"]`
- `elicitation/create` (client does not advertise `elicitation.form`)
- session compaction RFDs (`session.compaction` stays unadvertised)

Slash commands that OpenCode runs because a prompt starts with `/` are
agent-side; TeamPilot sends the user's text unchanged.

## UI

### Settings

On the OpenCode row in `pages/config/cli_config_section.dart`, a switch
mirroring Cursor: "Personal sessions use ACP chat" bound to
`opencodePersonalAcpDefault`.

Reuse `PersonalAcpSettingsRow`. Add `OpencodePersonalAcpSettingsRow`
next to the Cursor/Codex wrappers. Disabled on Android with the existing
shared ACP-desktop-only copy (`claudePersonalAcpAndroidDisabled` is
already reused by Cursor). No adapter install button.

One extra `_buildCliRow` branch for `CliTool.opencode`, same as Cursor
and Codex.

### Landing / personal compose

Landing does **not** grow a visible OpenCode ACP switch. Create writes
`AppSession.acp` from `resolveLaunchAcp` +
`readPersonalAcpDefault(context, cli)`. Selecting OpenCode with the
OpenCode switch off must not inherit Claude or Cursor's default.

Team compose has no extra OpenCode ACP control; mixed seats are stamped
from the same preference at create.

### Session chrome

ACP OpenCode personal sessions use the existing ACP chat center (no
live-terminal toggle), gated by `isAcpChatSession`. Mixed ACP seats use
the existing per-seat ACP runtime map (`ChatTab.memberAcpRuntimes`).

Permissions use the existing `AcpPermissionCard`. OpenCode has no
blocking client extensions, so ask/plan cards stay Cursor-only.

## File size / placement

| File | Rule |
|------|------|
| `services/cli/opencode/capabilities/acp.dart` | New file. Capability + translator. No Cursor extension methods. |
| `opencode_tool.dart` | Default-construct `OpencodeAcpCapability` and include it in `capabilities`. |
| `cli_config_section.dart` | Shared settings row + one extra `_buildCliRow` branch. |
| `session_preferences.dart` / cubit | Add `opencodePersonalAcpDefault` (default true) + setter. JSON omit-or-default-true like Cursor. |
| `member_acp_stamp.dart` / `SessionCreateRequest` / launch call sites | Thread `seedOpencodeMemberAcp`. |
| `services/acp/*` | Do not change. |
| `AcpChatRuntimeCubit` | Do not grow for OpenCode-specific updates. |

l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only.
Keys: `opencodePersonalAcpDefaultLabel` /
`opencodePersonalAcpDefaultDescription`. Reuse
`claudePersonalAcpAndroidDisabled` for the Android subtitle.
Description names `opencode acp`, and states that existing sessions keep
their original runtime; native teams and remote members still use the
terminal.

`AppKeys.opencodePersonalAcpSwitch`.

## Error handling

| Failure | Handling |
|---------|----------|
| `opencode` missing | Existing CLI install / not-found copy; session ended. |
| `acp` subcommand rejected (old CLI) | `AcpFlagRejected` then `AcpLaunchException` / `launchFailedVersion`. Copy is already CLI-agnostic. |
| Handshake timeout / malformed handshake | Frame log; launch failed. Do not probe another argv (only one candidate). |
| Agent crash after open | Inline system message + `processExited`. |
| User cancel | `session/cancel`; pending permission hold cancelled. |
| prompt `auth_required` | Turn `turnFailed` with generic `acpChatNotLoggedIn`. Not `launchFailedAdapter`. Do not send `authenticate`. |
| ACP attach failure | Do not fall back to PTY. |

## Out of scope

- `SshExecTransport` / Android ACP
- Native-team ACP (`--team-name` / OpenCode equivalent)
- Replacing PTY OpenCode
- `session/load` / `session/resume` / `session/fork` / persisting ACP session ids
- Advertising `fs/*`, `terminal/*`, `auth.terminal`, `elicitation.form`,
  `session.compaction`
- Passing `mcpServers` or `additionalDirectories` on `session/new`
- `opencode acp --login` terminal-auth flow
- Child-session chrome, usage meters, compaction summaries, slash-command
  palettes
- FlashskyAI ACP
- Generalizing the per-CLI preference/UI allow-lists into a map

## Testing

Constructor-injected fakes; cubit tests that need a home plane use
`setUpTestAppStorage()` / `tearDownTestAppStorage()`. Never invoke
`flutter test` directly; use `cd client && dart run tool/run_tests.dart`.

| Layer | Cases |
|-------|--------|
| `OpencodeAcpCapability` | argv is `[executable, 'acp']`; `agentExecutable` is the CLI binary; `buildEnvironment` keeps `OPENCODE_CONFIG_DIR` / `OPENCODE_DB` / `OPENCODE_AUTH_CONTENT` / `OPENCODE_CLI_CONFIG_CONTENT` from `baseEnv` and does not invent `HOME` from `sessionToolDir`; `authenticateMethodId` is null; `forwardSessionNewMcpServers` is false. |
| Translator | No blocking / notification client methods. RpcError stop text is the generic ACP error form. |
| Registry | `OpencodeCliTool` exposes `AcpCapability`. |
| Preferences | `opencodePersonalAcpDefault` defaults true, JSON round-trip, missing key → true, cubit setter. |
| `resolveLaunchAcp` | personal OpenCode + requested + desktop → true; team / Android / FlashskyAI → false; Claude / Cursor / Codex cases unchanged. Replace the current assertion that OpenCode is always false. |
| `readPersonalAcpDefault` | OpenCode reads the OpenCode preference, not Claude's. |
| `stampMemberAcp` | mixed local OpenCode seat follows `seedOpencodeMemberAcp`; Gemini still forced; native / Android / SSH false. |
| Settings UI | OpenCode row switch toggles the preference; Android disables it; no adapter button. |
| Connect | `acp` OpenCode attaches ACP runtime and does not open a PTY; `acp` false OpenCode still takes the shell path. Mixed OpenCode ACP seat attaches member ACP runtime. |

No live `opencode acp` in CI. Manual desktop check: personal OpenCode
with the switch on → ACP chat, permission card, catalog MCP from
isolated `opencode.json`; mixed local OpenCode seat with the switch on →
ACP seat + teammate-bus via staged config; switch off → new session /
seat still gets a terminal; existing PTY OpenCode sessions unchanged.

## Logging

Reuse `AcpFrameLogger`. Redact `OPENCODE_AUTH_CONTENT` if those frames
appear. Isolated `auth.json` / auth-content payloads must never land in
the frame log.
