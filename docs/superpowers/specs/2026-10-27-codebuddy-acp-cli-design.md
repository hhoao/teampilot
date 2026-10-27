# CodeBuddy CLI (ACP-only) Design

## Goal

Add the **CodeBuddy Code CLI** (`codebuddy`, alias `cbc`) as a first-class
TeamPilot launchable CLI. It speaks
ACP natively (`codebuddy --acp`) and is a Claude-Code-compatible fork
(`~/.codebuddy/settings.json`, `mcp.json`, `skills/`, `plugins/`, hooks,
`CODEBUDDY.md`, `CODEBUDDY_CONFIG_DIR`).

Scope (locked with the user, 2026-10-27):

- **ACP only. No PTY / terminal mode.** Chat, permissions, history, and
  status are the app-owned ACP stack (`AcpSessionRuntime` /
  `AcpChatRuntimeCubit`).
- **Full CLI feature surface otherwise**: provider/models, executable
  discovery + npm install, skills, MCP, hooks, plugins, prompt/memory,
  native commands (from `available_commands_update`), headless one-shot.
- Desktop local first. Android / SSH ACP stay out of scope for this phase
  (same gates as existing personal ACP).
- Personal sessions first. Registering `AcpCapability` is enough for the
  mixed-seat gate later; no `stampMemberAcp` seed in this phase.

## Evidence (local probe, codebuddy 2.177.0)

```
initialize  → agentCapabilities.loadSession=true, mainAgentSupport=false,
              multitaskSupport=true, authMethods=[iOA, external, internal, selfhosted]
session/new → { sessionId, models.availableModels[] } + config_option_update(mode)
session/update → usage_update {used,size,cost,_meta.usageByCategory}
                 session_info_update (_meta["codebuddy.ai/agentPhase"])
                 available_commands_update
                 tool_call / tool_call_update (standard ACP)
session/request_permission options: allow_always / allow / reject
session/prompt → { stopReason, _meta["codebuddy.ai/requestId"] }
```

- Auth uses the machine's existing login: `session/new` + `session/prompt`
  succeed with a fresh `CODEBUDDY_CONFIG_DIR`, so no `authenticate` call is
  needed (`authenticateMethodId = null`, Cursor-style).
- Agent → client notifications: `_codebuddy.ai/command` (`workspace_info`)
  and `_codebuddy.ai/modResidentInvalidate`. They are notifications (no
  `id`); no client response is required.
- `usage_update` already carries live cost, which the ACP meter can consume
  once the usage milestone lands.

## Layering

| Piece | Owner |
|-------|-------|
| `services/acp/*` | Unchanged protocol mechanics. No `fs` / `terminal` advertisement. |
| `CodebuddyCliTool` | `services/cli/codebuddy/codebuddy_tool.dart` |
| ACP argv / env / translator | `capabilities/acp.dart` — `[codebuddy, --acp]`, `CODEBUDDY_CONFIG_DIR`, no authenticate |
| Provider / models | `capabilities/provider.dart` — `models.json` + `settings.json` (`model`, `reasoningEffort`); official preset + custom OpenAI-compatible |
| Executable / installer | `capabilities/executable.dart` — npm `@tencent-ai/codebuddy-code`, binary `codebuddy` |
| Skills | shared `DefaultSkillCapability` → `<config>/skills` |
| MCP | `capabilities/mcp.dart` → `<config>/mcp.json` (`mcpServers`) |
| Hooks | `capabilities/hook_writer.dart` → Claude-family `settings.json` dialect |
| Plugins | `capabilities/plugin.dart` → Claude-flavor registry writer, `.codebuddy-plugin` with `.claude-plugin` fallback |
| Prompt | `capabilities/prompt.dart` → `<config>/CODEBUDDY.md` |
| Headless | `capabilities/headless.dart` → `codebuddy -p --output-format stream-json` |
| History | ACP app-owned transcript (`acp-transcript.jsonl`). `AiHistoryCapability` is a stub: never call `session/load`. |
| Launch policy | ACP-only personal sessions: `AppSession.acp` inferred at create (Gemini branch), `willLaunchPersonalAcp` true on desktop. |

No new `CliTool.codebuddyAcp`. No `if (cli == codebuddy)` in
`AcpSessionRuntime` / `AcpChatRuntimeCubit`; quirks live on the capability
and translator.

## Config home

`CODEBUDDY_CONFIG_DIR` = the per-session tool dir TeamPilot already
materializes. The CLI creates its own subdirs (`projects/`, `logs/`,
`local_storage/`, `plugins/`) inside it; auth continues to resolve from the
machine's login.

Writes performed by TeamPilot:

- `settings.json` — `model`, `reasoningEffort` (merged, never clobbering
  user keys)
- `models.json` — only when the provider declares a custom `baseUrl` /
  `apiKey`; `apiKey` is written as `"${CODEBUDDY_API_KEY}"` and the key is
  passed in the process env, so the secret is not persisted to disk
- `CODEBUDDY_AUTH_TOKEN` — the provider's isolated access token (see
  Sign-in), injected into the agent process env
- `mcp.json`, `skills/`, `plugins/`, `settings.json#hooks`, `CODEBUDDY.md`

## Session model

- New personal sessions with `CliTool.codebuddy` are `acp: true` by default
  on desktop (inferred at create, like Gemini).
- Android: ACP not available → session create stays non-ACP and the compose
  surface hides the CLI as unsupported on that target.
- Reconnect trusts the persisted `AppSession.acp`, not a preference.

## Testing

- Capability unit tests: ACP argv/env, provider `models.json` shape,
  MCP `mcp.json` merge, hook render `settings.json` fragment, executable
  name/package.
- Registry test: every `CliTool` registers the required capabilities.
- Launch-policy tests: `willLaunchPersonalAcp` / `AppSession.acp` inference
  for CodeBuddy on desktop vs Android.
- `test/integration/codebuddy_acp_local_smoke_test.dart` (tag
  `integration`): real `codebuddy --acp` through `productionAcpSpawner` +
  `AcpSessionRuntime`, one prompt turn; skipped when the binary is absent.

## Sign-in (isolated credentials)

The CLI has no `auth login` subcommand; login only exists in its TUI
(`/login` → login-method picker → browser hand-off → "Waiting for auth…").
Credentials are **not** stored under `CODEBUDDY_CONFIG_DIR`; they live at
`<homedir>/.local/share/CodeBuddyExtension/Data/Public/auth/*.info`
(macOS `~/Library/Application Support/…`, Windows `%USERPROFILE%\AppData\Local\…`).

TeamPilot isolates them per provider:

- `InteractiveCliLoginCapability` opens `CodebuddyLoginDialog`, an embedded
  Alacritty terminal running `codebuddy` with **`HOME` / `USERPROFILE` pinned
  to a per-provider `<appData>/cli-login/codebuddy/<provider>/home`** (and
  `CODEBUDDY_CONFIG_DIR` to `…/config`), so the user's global CLI login is
  never read or overwritten. Each provider row keeps its own login state, so
  multiple CodeBuddy providers can hold different accounts at the same time.
- The login workspace is pre-trusted in the isolated `settings.json`, so a
  fresh home shows the login-method picker (or the composer when that login
  home is already signed in) instead of a trust question.
- Auto-input: `/login` is typed only when the TUI shows its **composer**
  (account switch). A startup login picker is left to the user — pressing
  Enter there would pick an account type blindly. A toolbar button can send
  `/login` manually.
- On **Done**, `execute(login)` reads the newest `*.info` from the isolated
  home and copies `accessToken` / `expiresAt` / `refreshToken` into
  `<appData>/providers/codebuddy/<provider>.auth.json` (chmod 600 on Unix).
  Missing file → `verifyFailed`, nothing stored.
- Sessions and headless runs inject `CODEBUDDY_AUTH_TOKEN` from that
  provider store, so each provider row can hold a different account and the
  machine login is never used while a provider token exists.
- `probe()` is ready only for a non-expired provider token (or a provider
  API key); the action stays visible so accounts can be switched.

Limitations: the env-token path does not persist CLI-side refresh, so an
expired 30-day access token needs a fresh Sign in; the token carries no
enterprise/iOA domain override (standard product only). Without a provider
token, sessions fall back to the machine login.

## Out of scope (follow-ups)

- Mixed-team ACP seats + `stampMemberAcp` seed
- Native JSONL history/usage parsing (`~/.codebuddy/projects/*.jsonl`)
- `loadSession` / resume via the CLI's own transcript
- Android / SSH transports
- CodeBuddy private `_meta` (agent teams, member events, config options)
