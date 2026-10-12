# Codex ACP Session Design

## Goal

Add an opt-in Agent Client Protocol (ACP) path for **personal Codex
sessions**, without replacing the existing PTY Codex product (team, plugins,
hooks, ChatGPT Official login, terminal view).

Gemini remains ACP-only. Claude remains personal-opt-in ACP. Codex stays
PTY-by-default. A Codex session that opts into ACP uses the same
`AcpSessionRuntime` / chat / permission-card / app-owned transcript stack.

Decisions locked with the user (2026-10-12):

- Clone the **shipped** Claude ACP surface (settings switch + preference at
  create). Do not generalize Claude's preference/UI into a per-CLI map.
- Keep PTY Codex. Do not replace it. Do not speak `codex app-server`
  from TeamPilot; spawn the npm adapter.
- Personal Codex may launch as ACP chat. Default for new personal Codex
  sessions is **off**.
- Official ChatGPT login **and** API-key / third-party providers both work
  in this phase.
- Team sessions never use ACP in this phase.
- Protocol stack stays vendored `acpd` + `AcpProcessTransport`.
- Desktop-local only. Android / SSH exec stay out of scope (no
  `SshExecTransport` yet).
- Credentials: reuse PTY `CodexHomeProvisioner` via the existing ACP
  `contributeLaunch` path. Official must **not** inject `OPENAI_API_KEY` /
  `CODEX_API_KEY` (host env keys would skip ChatGPT OAuth / force API
  billing). Key providers inject the resolved key.

## Why an adapter process

Codex has no native `codex --acp`. The ACP peer is a separate npm agent:

- Package: `@agentclientprotocol/codex-acp`
- Executable: `codex-acp`

TeamPilot spawns that binary over stdio (NDJSON JSON-RPC). Internally the
adapter starts Codex App Server and translates ACP ↔ Codex. TeamPilot never
embeds the adapter in the Flutter isolate, and never talks to
`codex app-server` itself.

```
PTY (default):  TeamPilot --PTY--> codex
ACP (opt-in):   TeamPilot --ACP stdio--> codex-acp --> Codex App Server
```

## Layering

Mechanism vs declaration stays as in the Gemini spec
(`docs/superpowers/specs/2026-09-12-acp-gemini-session-design.md`) and the
Claude adapter spec
(`docs/superpowers/specs/2026-10-09-claude-acp-session-design.md`).

| Piece | Owner |
|-------|--------|
| `services/acp/*` | Unchanged protocol mechanics. |
| `isAcpChatSession` | Session flag, not `cli == gemini`. Unchanged. |
| `CodexAcpCapability` | `services/cli/codex/capabilities/acp.dart` — adapter argv, env, translator. |
| `CodexAcpAdapterInstaller` | `services/cli/codex/capabilities/acp_adapter_installer.dart` — npm install of `@agentclientprotocol/codex-acp` only. |
| `CodexCliTool` | Gains `AcpCapability`. Presence of the capability does **not** mean every Codex session is ACP. |
| Settings default | `SessionPreferences.codexPersonalAcpDefault` (`false`). |
| Session fact | `AppSession.acp` (bool). Reconnect trusts this, not the preference. |

No new `CliTool.codexAcp`. `docs/cli-architecture.md` does not list
`AcpCapability` today; this phase does not require a docs sweep beyond this
spec.

Connect already branches on `isAcpChatSession` before member/shell connect
(`SessionConnectExecutor` / `SessionLaunchService.attachAcpRuntime`). Codex
ACP rides that branch. The executor must not grow `if (cli == codex)`.

## Session model

### `AppSession.acp`

Unchanged from Claude:

- Type: `bool`, default `false`.
- JSON: omit when false; write `"acp": true` when true.
- `fromJson` when the key is missing: Gemini simple → `true`; otherwise
  `false` (legacy Codex PTY rows stay PTY).
- Team create (`sessionTeam` non-empty) still forces `acp = false`.

### `isAcpChatSession`

```
bool isAcpChatSession(AppSession session) =>
    session.isSimple && session.acp;
```

### Preference vs session

| Store | Role |
|-------|------|
| `SessionPreferences.codexPersonalAcpDefault` | Default for **new** personal Codex launches. Default `false`. |
| `SessionPreferences.claudePersonalAcpDefault` | Unchanged. Do not merge the two into one field. |
| `AppSession.acp` | Durable fact for this session. Reconnect / open-existing uses it. |

Changing the Codex preference does not rewrite existing sessions. It does
not change Claude's preference.

Claude's shipped default is currently `true`; Codex's default stays
`false` even so. Missing JSON key → `false` (not "inherit Claude").

## Launch

### Adapter executable (not `codex`)

`shellFactory.executableFor(CliTool.codex)` is the **PTY** binary. Spawning
it as the ACP agent is wrong.

`CodexAcpCapability.agentExecutable` returns the located `codex-acp` path.
`launchArgCandidates` returns `[[agentExecutable]]` (no `--acp` flag), same
shape as Claude.

Locate the adapter the same way as `locateClaudeAcpAdapter`: `PATH`, then
`~/.local/bin`, then the TeamPilot node prefix
(`$HOME/.local/share/<app-data>/toolchain/node/current/bin`). If none match,
return the bare name `codex-acp` so spawn fails closed with the adapter
l10n error.

Do **not** change `CodexExecutableCapability.npmPackage` (`@openai/codex`).
The adapter is a separate installer class.

Connect **never** auto-installs the adapter (same as shipped Claude; the
Claude spec's "auto-install on missing" sentence is not the shipped
behavior). Install is user-initiated from the Codex settings row.

### Environment

ACP connect already runs the same simple `contributeLaunch` /
`ensureLinked` path as PTY (`prepareAcpLaunchEnvironment`), then
`CodexAcpCapability.buildEnvironment` patches that env. `buildEnvironment`
stays **synchronous**. It must not call `CodexHomeProvisioner` a second
time.

`contributeLaunch` (already implemented for PTY Codex) materializes
isolated `CODEX_HOME` under the session runtime tool dir
(`…/runtime/codex`): `auth.json` + `config.toml`, Official tokens copied
from the stored provider auth path, API-key / proxy auth generated as
today. `baseEnv` therefore already contains `CODEX_HOME` (and MCP OAuth
env when present).

`buildEnvironment` then:

- Preserve `baseEnv` (`PATH` at minimum).
- Set `CODEX_HOME` to `sessionToolDir` (the slot is already
  `…/runtime/codex`; do not nest another `/codex`). Never point at the
  user's `~/.codex`.
- Set `CODEX_PATH` to the Codex CLI binary TeamPilot would spawn for PTY.
  Inject a path source on `CodexAcpCapability` (bootstrap / tests); default
  `'codex'`. Do not extend the shared `AcpCapability.buildEnvironment`
  signature for this.
- Empty-string-unset `OPENAI_API_KEY` and `CODEX_API_KEY` first (same
  "unset" signal as Claude's `ANTHROPIC_*` keys) so a host env key cannot
  leak into Official launches. `mergeAcpProcessEnvironment` already drops
  empty values.
- Official (`isOfficialCodexOAuthProvider`): leave those keys unset. Auth
  is the provisioned `auth.json` tokens. Do not set a Claude-style
  `CCGUI_CLI_LOGIN_AUTHORIZED` equivalent unless the adapter documents one.
- API-key / third-party: write the resolved key to `OPENAI_API_KEY` and
  `CODEX_API_KEY` (adapter documents both names).
- Do not set `INITIAL_AGENT_MODE`, Gemini's `SURFACE=teampilot`, or PTY's
  `--dangerously-bypass-approvals-and-sandbox` (that flag is a Codex CLI
  argv, not an adapter env). Model / sandbox / MCP already live in the
  provisioned `config.toml`.

Credential accessors are injected from `CodexBootstrapEntry` at
`registerBuiltInCliTools` (`acpAuthSource`, plus the `CODEX_PATH` source).
Mirror `claudeAcpAuthForProvider` / `pickClaudeAcpProvider`:

- Selected Codex provider id, else first Official Codex row.
- Official → `CodexAcpAuth(official: true)` and no key fields.
- Otherwise read provider env / `apiKey` (`OPENAI_API_KEY` field).

### Failure policy

Adapter missing, handshake failure, or Official-not-logged-in → l10n error
on the session. **Do not** fall back to PTY for the same connect. Mixed
runtime on one session is forbidden.

Do **not** add a pre-spawn `auth.json` probe. Classification already exists:

- Missing adapter: `AcpSessionRuntime` throws `acpLaunchFailedAdapter` when
  `agentExecutable != cliExecutable` and the spawn error is "executable
  not found". Codex hits this because the agent is `codex-acp`, not `codex`.
- Official not logged in: existing `lastAuthNotice` / cubit system row,
  with Codex copy injected at attach (below). If the adapter's auth notice
  shape needs a one-line translator map, add it then — not a new gate.

### Translator

`CodexAcpTranslator` starts as a thin mapper (raw `RpcError` → surfaced
string; `flagCandidates` empty). Adapter-specific abort/cancel phrases are
added only when a real quirk shows up in logs — do not copy Gemini's
gemini-cli#6656 workaround.

### History

ACP Codex history is the app-owned `AcpChatTranscriptWriter` path already
used by Gemini/Claude ACP. Do not read `$CODEX_HOME/sessions/**/rollout-*.jsonl`
for `session.acp` rows. `CodexAiHistoryCapability` stays the PTY resume
path.

`session/load` resume UI is out of scope (same as Claude ACP).

## UI

Clone shipped Claude, not the unused compose-toggle sentence in the Claude
spec. New sessions read the settings preference at create. There is no
extra compose widget.

### Settings

On the Codex row in `pages/config/cli_config_section.dart` (desktop only):

- Switch: "Personal sessions use ACP chat" bound to
  `SessionPreferences.codexPersonalAcpDefault`.
- Button: install `@agentclientprotocol/codex-acp` via
  `CodexAcpAdapterInstaller` / a new `InstallJobKeys.codexAcpAdapter()`
  enqueue, parallel to `installClaudeAcpAdapter`.

Disabled on Android (`Platform.isAndroid`) with
`codexPersonalAcpAndroidDisabled`. The sentences are the same policy as
Claude's Android copy; use a Codex-named key so the Codex row does not
call a Claude getter.

### Landing / personal compose

`resolveLaunchAcp` today allows only personal Claude on desktop. Extend it
so `requested` also survives for personal Codex on desktop. Team creates
and Android stay `false`. Gemini still does not use this function.

`unbound_compose_body` currently always passes
`readClaudePersonalAcpDefault`. Change that to pick the preference for the
draft CLI (Claude vs Codex). Other CLIs pass `requested: false`.

`buildWorkspaceConversationCreateRequest` already funnels through
`resolveLaunchAcp`; once that gate includes Codex, create persists
`AppSession.acp` correctly.

Gemini compose stays ACP-only (no toggle). Team compose has no Codex ACP
control.

### Session chrome

ACP Codex sessions use the existing ACP chat center (no live-terminal
toggle). `isAcpChatSession` already gates this.

## l10n

Edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only.

`AcpChatStrings` is injected at attach. Today's host copy names Claude
(`acpLaunchFailedAdapter`, `acpChatNotLoggedIn`). `attachAcpRuntime`
already knows `session.cli`; when it is Codex, inject Codex strings.
Gemini and Claude keep the existing keys.

| Key | Use |
|-----|-----|
| `codexPersonalAcpDefaultLabel` | Settings switch title. |
| `codexPersonalAcpDefaultDescription` | Settings switch body; name `codex-acp`. |
| `codexPersonalAcpAndroidDisabled` | Same policy sentence as Claude's Android copy. |
| `claudeAcpAdapterInstallButton` | Reuse; the shipped string is already generic ("Install ACP adapter"). |
| `codexAcpLaunchFailedAdapter` | `codex-acp` missing / not startable. |
| `codexAcpChatNotLoggedIn` | Official ChatGPT login missing. |

Do not retarget Gemini's "this CLI version does not support ACP" string at
Codex — Codex is adapter-based, not flag-based. Do not rewrite
`AcpChatStrings` into a per-CLI map.

## Out of scope

- `SshExecTransport` / Android ACP
- Team roster / TeamBus ACP members
- Replacing PTY Codex
- Direct `codex app-server` / skipping `@agentclientprotocol/codex-acp`
- OpenCode ACP
- `session/load` resume UI
- Advertising `fs/*` / `terminal/*` client capabilities (stay false, same
  isolation as Gemini/Claude phase 1)
- `INITIAL_AGENT_MODE` / adapter AIR sandbox extras
- Generalizing Claude+Codex preferences into one per-CLI map
- A compose-time ACP toggle beyond the settings default

## Testing

Constructor-injected fakes; cubit tests that need a home plane use
`setUpTestAppStorage()` / `tearDownTestAppStorage()`.

Never invoke `flutter test` directly; use `cd client && dart run
tool/run_tests.dart <paths>`. Inner loop is `flutter analyze` plus one
test file.

| Layer | Cases |
|-------|--------|
| Preferences | `codexPersonalAcpDefault` defaults false; omitted JSON → false; copyWith / round-trip; Claude field unchanged. |
| `resolveLaunchAcp` | personal Codex + requested → true; default Codex requested false → false; teamed Codex → false; Android Codex → false; personal Claude behavior unchanged. |
| Compose create | draft CLI Codex + preference on → `AppSession.acp` true; Codex + preference off → false; Claude still reads the Claude preference. |
| `CodexAcpCapability` | argv is adapter only (not `codex --acp` / not `codex app-server`); Official env has `CODEX_HOME` + `CODEX_PATH` and empty/omitted API keys; API-key env sets `OPENAI_API_KEY` and `CODEX_API_KEY`; `CODEX_HOME` is `sessionToolDir` not `~/.codex`. |
| Adapter locator / installer | package is `@agentclientprotocol/codex-acp`; job target distinct from `CliTool.codex`; `CodexExecutableCapability.npmPackage` still `@openai/codex`. |
| Connect executor | `acp` Codex attaches ACP runtime and does not open a PTY; default Codex still takes the shell path. |
| ACP strings | Codex attach uses `codexAcpLaunchFailedAdapter` / `codexAcpChatNotLoggedIn`; Claude attach still uses the Claude keys. |
| Settings | switch writes `codexPersonalAcpDefault`; install button enqueues the Codex adapter job; hidden/disabled on Android. |

No live `codex-acp` in CI. Manual desktop check: install adapter, personal
Codex + ACP on + Official login, prompt + permission card; repeat with an
API-key provider; then a personal Codex with ACP off still gets a
terminal.

## Logging

Reuse `AcpFrameLogger` (in/out/stderr). App-wide env redaction already
masks keys whose names contain `KEY` / `AUTH` (`OPENAI_API_KEY`,
`CODEX_API_KEY`, tokens in `auth.json` logs). Extend the frame logger only
if ACP frames bypass that helper.
