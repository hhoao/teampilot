# Claude ACP Session Design

## Goal

Add an opt-in Agent Client Protocol (ACP) path for **personal Claude Code
sessions**, without replacing the existing PTY Claude product (team, plugins,
hooks, Official login, terminal view).

Gemini remains ACP-only. Claude remains PTY-by-default. A session that opts
into ACP uses the same `AcpSessionRuntime` / chat / permission-card stack as
Gemini.

Decisions locked with the user (2026-10-09):

- Keep PTY Claude. Do not replace it.
- Add one configuration: personal Claude may launch as ACP chat.
- Team sessions never use ACP in this phase.
- Protocol stack stays vendored `acpd` + `AcpProcessTransport`. Do not take
  FlutterFlow `dart_acp_claude` in-process.
- Desktop-local only. Android / SSH exec stay out of scope (no
  `SshExecTransport` yet).
- Credentials: inject API key when the chosen provider is key-based; Official
  login reuses isolated Claude config dir and **must not** set
  `ANTHROPIC_API_KEY` (that forces API billing).

## Why an adapter process

Claude Code has no native `--acp`. The ACP peer is a separate npm agent:

- Package: `@agentclientprotocol/claude-agent-acp`
- Executable: `claude-agent-acp`

TeamPilot spawns that binary over stdio (NDJSON JSON-RPC). Internally the
adapter talks to the Claude Agent SDK / local Claude Code. TeamPilot never
embeds the adapter in the Flutter isolate.

```
PTY (default):  TeamPilot --PTY--> claude
ACP (opt-in):   TeamPilot --ACP stdio--> claude-agent-acp --> Claude Agent SDK
```

## Layering

Mechanism vs declaration stays as in the Gemini spec
(`docs/superpowers/specs/2026-09-12-acp-gemini-session-design.md`).

| Piece | Owner |
|-------|--------|
| `services/acp/*` | Unchanged protocol mechanics. |
| `isAcpChatSession` | Session flag, not `cli == gemini`. |
| `ClaudeAcpCapability` | `services/cli/claude/capabilities/acp.dart` — adapter argv, env, translator. |
| `ClaudeCliTool` | Gains `AcpCapability` like Gemini. Presence of the capability does **not** mean every Claude session is ACP. |
| Settings default | `SessionPreferences.claudePersonalAcpDefault` (false). |
| Session fact | `AppSession.acp` (bool). Reconnect trusts this, not the preference. |

No new `CliTool.claudeAcp`.

## Session model

### `AppSession.acp`

- Type: `bool`, default `false`.
- JSON: omit when false; write `"acp": true` when true.
- `fromJson` when the key is missing:
  - `cli == gemini` and `sessionTeam` empty → `true` (legacy Gemini ACP rows).
  - otherwise → `false` (legacy Claude PTY rows).
- Create paths that already spawn Gemini ACP must persist `acp: true` going
  forward so the legacy special case can be dropped later.

### `isAcpChatSession`

```
bool isAcpChatSession(AppSession session) =>
    session.isSimple && session.acp;
```

Team sessions (`sessionTeam` non-empty) are never ACP, even if a caller
passes `acp: true`. `createSession` forces `acp = false` when
`sessionTeam` is non-empty.

### Preference vs session

| Store | Role |
|-------|------|
| `SessionPreferences.claudePersonalAcpDefault` | Default for **new** personal Claude launches. Default `false`. |
| `AppSession.acp` | Durable fact for this session. Reconnect / open-existing uses it. |

Changing the preference does not rewrite existing sessions.

## Launch

`SessionConnectExecutor` already branches on `isAcpChatSession` before
member/shell connect. After the session flag exists, Claude ACP rides that
branch with no `if (cli == claude)` at the executor.

`SessionLaunchService.attachAcpRuntime` today hardcodes Gemini in two places
and must become CLI-agnostic:

1. `session.cli ?? CliTool.gemini` → require `session.cli` (ACP sessions
   always have a CLI).
2. `sessionRuntimeToolDir(..., 'gemini')` → use `session.cli!.value` so
   Claude ACP isolates under the Claude slot, not Gemini's.

### Adapter executable (not `claude`)

`shellFactory.executableFor(CliTool.claude)` is the **PTY** binary. Spawning
it as the ACP agent is wrong.

Extend `AcpCapability`:

```dart
/// Binary that speaks ACP on stdio. Gemini returns [cliExecutable].
/// Claude ACP returns the located `claude-agent-acp` path.
String agentExecutable(String cliExecutable);
```

`launchArgCandidates(agentExecutable)` for Claude returns
`[[agentExecutable]]` (no `--acp` flag). Gemini stays
`[[gemini, --acp], [gemini, --experimental-acp]]`.

`attachAcpRuntime` / `productionAcpSpawner` pass
`capability.agentExecutable(cliExecutable)` into `AcpSessionRuntime.start`.

Locate the adapter the same way other npm CLIs are located (PATH, then
TeamPilot node prefix). If missing, auto-install
`@agentclientprotocol/claude-agent-acp` via the existing npm installer
channel (a small installer class on the Claude ACP capability — **not** by
changing `ClaudeExecutableCapability.npmPackage`, which stays
`@anthropic-ai/claude-code`).

Optional later: a dedicated adapter path row in CLI settings. Not in this
phase; PATH + auto-install is enough.

### Environment

ACP connect skips the PTY launch/manifest pipeline, so credentials must be
assembled in `ClaudeAcpCapability.buildEnvironment` (plus a small pre-spawn
provision if files need copying). Reuse Claude's existing simple-launch
provider resolution (`ClaudeProviderCapability` / credentials service), not
a new auth stack.

- Preserve `baseEnv` (`PATH` at minimum, same as Gemini).
- Always set `CLAUDE_CONFIG_DIR` to an isolated dir under `sessionToolDir`
  (`…/claude`), never the user's `~/.claude`.
- API-key / auth-token providers: copy the resolved
  `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN` into the agent env.
- Official login: do **not** set those keys (they force API billing). Copy
  or link `.credentials.json` from the provider credentials dir into
  `CLAUDE_CONFIG_DIR` (same files PTY Official already uses).
- Set `CCGUI_CLI_LOGIN_AUTHORIZED=1` when Official credentials are present,
  matching `ClaudeProviderCredentialsService.loginEnvironment`.
- Do not set Gemini's `SURFACE=teampilot` unless the adapter documents an
  equivalent.

Credential accessors are injected from `ClaudeBootstrapEntry` at
`registerBuiltInCliTools`, same pattern as `GeminiBootstrapEntry`.

### Failure policy

Adapter missing, install failure, or handshake failure → l10n error on the
session. **Do not** fall back to PTY for the same connect. Mixed runtime on
one session is forbidden.

### Translator

`ClaudeAcpTranslator` starts as a thin mapper (raw `RpcError` → surfaced
string; `flagCandidates` empty). Adapter-specific abort/cancel phrases are
added only when a real quirk shows up in logs — do not copy Gemini's
gemini-cli#6656 workaround.

## UI

### Settings

On the Claude row in `pages/config/cli_config_section.dart` (desktop only),
a switch: "Personal sessions use ACP chat" bound to
`SessionPreferences.claudePersonalAcpDefault`.

Hidden or disabled on Android (`Platform.isAndroid`) with existing copy
that Android runs CLIs over SSH.

### Landing / personal compose

When the selected CLI is Claude and the platform is desktop, show the same
choice (switch or segmented control) initialized from the preference.
The value written at `createSession` is `AppSession.acp`.

Gemini compose stays ACP-only (no toggle). Team compose has no Claude ACP
control.

### Session chrome

ACP Claude sessions use the existing ACP chat center (no live-terminal
toggle), same as Gemini (`isAcpChatSession` already gates this).

## Out of scope

- `SshExecTransport` / Android ACP
- Team roster / TeamBus ACP members
- Replacing PTY Claude
- In-process `dart_acp_claude` / switching off `acpd`
- Codex / OpenCode ACP
- `session/load` resume UI
- Advertising `fs/*` / `terminal/*` client capabilities (stay false, same
  isolation as Gemini phase 1)

## Testing

Constructor-injected fakes; cubit tests that need a home plane use
`setUpTestAppStorage()` / `tearDownTestAppStorage()`.

| Layer | Cases |
|-------|--------|
| `AppSession` JSON | omit `acp` → Claude false, Gemini simple true; `"acp": true` round-trip; team create forces false. |
| `isAcpChatSession` | Gemini simple true; Claude simple default false; Claude simple `acp` true; teamed Claude false. |
| `ClaudeAcpCapability` | argv is adapter only (not `claude --acp`); API-key env sets `ANTHROPIC_API_KEY`; Official env omits it; config dir under `sessionToolDir`. |
| `AcpSessionRuntime` | still CLI-agnostic; a Claude plan + fake spawner opens a session. |
| Connect executor | `acp` Claude attaches ACP runtime and does not open a PTY; default Claude still takes the shell path. |
| Preferences | default false; copyWith / JSON round-trip. |

No live `claude-agent-acp` in CI. Manual desktop check: install adapter,
personal Claude + ACP on, prompt + permission card, then a second personal
Claude with ACP off still gets a terminal.

## Logging

Reuse `AcpFrameLogger` (in/out/stderr). App-wide log redaction already
covers `ANTHROPIC_API_KEY`; extend the frame logger only if those frames
bypass that helper.
