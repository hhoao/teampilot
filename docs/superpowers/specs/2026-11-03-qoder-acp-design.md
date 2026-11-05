# Qoder CLI (ACP-only) Design

## Goal

Add **Qoder CLI** (`qodercli`) as a first-class TeamPilot launchable CLI. It
speaks ACP natively (`qodercli --acp`) and is a Claude-Code-compatible fork
(`settings.json`, `mcp.json`, `skills/`, `plugins/`, hooks, `AGENTS.md`,
`QODER_CONFIG_DIR`).

Scope (locked with the user, 2026-11-03):

- **ACP only. No PTY / terminal mode.** Chat, permissions, history, and
  status are the app-owned ACP stack (`AcpSessionRuntime` /
  `AcpChatRuntimeCubit`).
- **Full CLI feature surface otherwise**: provider/models, executable
  discovery + install, skills, MCP, hooks, plugins, prompt/memory, native
  commands (from `available_commands_update`), headless one-shot, usage.
- **Credentials: provider-isolated login (option 1).** Each provider row owns
  its own Qoder account. The machine's `~/.qoder` login is only a read-only
  fallback when no provider account exists.
- **Mixed-team ACP seats included.** Because Qoder is ACP-only, every mixed
  Qoder member becomes an ACP seat wherever the existing mixed-seat gates
  pass (local or SSH transport, not Android). TeamBus `teammate-bus` is
  staged into the seat's `mcp.json` instead of `session/new`.
- Desktop local first for personal sessions. Android ACP stays out of scope
  for this phase (same gates as existing personal ACP).

## Evidence (local probe, qodercli 1.1.81)

```
initialize    → protocolVersion 1, agentInfo {name: qoder-cli, version},
                authMethods [{id: qodercli-login}],
                loadSession: true,
                sessionCapabilities {additionalDirectories, close, delete,
                                     fork, list, resume},
                promptCapabilities {image, embeddedContext},
                mcpCapabilities {http, sse},
                _meta.qoder.promptQueueing
session/new   → {sessionId,
                 modes: default | acceptEdits | auto | dontAsk | yolo,
                 models: availableModels[], currentModelId,
                 configOptions: [{id: mode}, …]}
session/update → available_commands_update
                 agent_message_chunk / agent_thought_chunk
                 tool_call / tool_call_update (standard ACP)
session/prompt → {stopReason, userMessageId,
                  usage {inputTokens, outputTokens, totalTokens},
                  _meta.quota {token_count, model_usage[]}}
```

Config isolation probe:

```
QODER_CONFIG_DIR=<fresh dir>  → session/new fails -32000
                               "Authentication required: Authentication is required."
                               <fresh dir>/.auth is created empty
QODER_CONFIG_DIR=<dir> + copy of ~/.qoder/.auth/{user,machine_id}
                              → session/new succeeds; prompt turn succeeds
QODER_CONFIG_DIR=<dir> qodercli status
                              → "Username: …" or "Account: Not logged in"
```

Key consequence: unlike CodeBuddy, `QODER_CONFIG_DIR` isolates **both** config
and credentials. A session config dir that is not seeded with `.auth` cannot
authenticate, and machine login is never consulted implicitly.

Other CLI surface verified:

- `--acp` is **hidden** (not in `--help`) but accepted; unknown flags exit 1,
  so an unsupported flag is detectable.
- `-p/--output-format text|json|stream-json` headless works.
- `mcp`, `skills`, `plugins`, `login`, `status`, `--config-dir`,
  `--permission-mode`, `--model`, `--reasoning-effort`, `--thinking`,
  `--settings`, `--mcp-config` exist.
- `<QODER_CONFIG_DIR>/skills/<name>/SKILL.md` is discovered by
  `qodercli skills list`.
- Project memory: `AGENTS.md` in the cwd and `AGENTS.md` in
  `QODER_CONFIG_DIR` are both read by the agent (verified with marker words).
  The config-dir copy is where TeamPilot stages its managed prompt.
- Plugins use `.qoder-plugin/plugin.json`; enablement lives in
  `settings.json#enabledPlugins`.
- History: `<QODER_CONFIG_DIR>/projects/<slug>/<session-id>.jsonl`
  (Claude-compatible JSONL).

## Layering

| Piece | Owner |
|-------|-------|
| `services/acp/*` | Unchanged protocol mechanics. No `fs` / `terminal` advertisement. |
| `QoderCliTool` | `services/cli/qoder/qoder_tool.dart` |
| ACP argv / env / translator | `capabilities/acp.dart` — `[qodercli, --acp]`, `QODER_CONFIG_DIR`, no authenticate |
| Provider / models | `capabilities/provider.dart` — account-only preset, models from ACP + `session/set_model` |
| Credentials / login | `provider/qoder_auth_store.dart`, `provider/qoder_login_dialog.dart` |
| Executable / installer | `capabilities/executable.dart` — npm `@qoder-ai/qodercli`, binary `qodercli` |
| Skills | shared `DefaultSkillCapability` → `<config>/skills` |
| MCP | `capabilities/mcp.dart` → `<config>/mcp.json` (`mcpServers`) |
| Hooks | `capabilities/hook_writer.dart` → Claude-family `settings.json#hooks` |
| Plugins | `capabilities/plugin.dart` → `.qoder-plugin` + `settings.json#enabledPlugins` |
| Prompt | `capabilities/prompt.dart` → `<config>/AGENTS.md` |
| Native commands | `capabilities/native_commands.dart` ← `available_commands_update` |
| Headless | `capabilities/headless.dart` → `qodercli -p --output-format stream-json` |
| History | ACP app-owned transcript (`acp-transcript.jsonl`). `AiHistoryCapability` is a stub: never call `session/load`. |
| Usage | `capabilities/usage/session_usage.dart` — prompt-result `usage` + `_meta.quota`, zero-cost when absent |
| Launch policy | ACP-only personal sessions: `AppSession.acp` inferred at create (Gemini/CodeBuddy branch), `willLaunchPersonalAcp` true on desktop. Mixed seats: `CliTransportCapability(supported: {acp})` → `launchesAcpOnly` stamps every Qoder member ACP where the generic gates pass. |
| Team seat MCP | `forwardSessionNewMcpServers = false`; `prepareTeamConnect` stages `teammate-bus` into `<config>/mcp.json` (the existing mixed-seat path, no TeamBus change). |

No new `CliTool.qoderAcp`. No `if (cli == qoder)` in `AcpSessionRuntime` /
`AcpChatRuntimeCubit`; quirks live on the capability and translator.

## Config home

`QODER_CONFIG_DIR` = the per-session tool dir TeamPilot already materializes
(`…/runtime/qoder`).

Writes performed by TeamPilot:

- `.auth/user`, `.auth/machine_id` — seeded from the provider credential store
  (mode 0600); absent provider store falls back to a read-only copy of
  `~/.qoder/.auth/{user,machine_id}`
- `settings.json` — merged `hooks`, `enabledPlugins`, `model`,
  `reasoningEffort`; never clobber unrelated user keys
- `mcp.json` — `mcpServers`
- `skills/`, `plugins/`, `AGENTS.md` (managed prompt; the CLI reads both this
  file and the workspace's own `AGENTS.md`, which TeamPilot leaves untouched)

The session never writes to `~/.qoder`; the fallback copy is one-way.

## Credentials (provider-isolated login)

Qoder credentials are an **opaque blob**: `~/.qoder/.auth/user` plus
`.auth/machine_id`. TeamPilot does not parse or refresh them.

- `InteractiveCliLoginCapability` opens `QoderLoginDialog`, an embedded
  Alacritty terminal running `qodercli login` with `HOME` / `USERPROFILE`
  pinned to `<appData>/cli-login/qoder/<provider>/home` and
  `QODER_CONFIG_DIR` to `…/config`.
- `qodercli login` is browser-based (prints an authorization URL and waits).
  The dialog surfaces the CLI output; the user completes the browser flow.
- On **Done**, `execute(login)` copies `.auth/user` + `.auth/machine_id` from
  the isolated login config into `<appData>/providers/qoder/<provider>.auth/`
  (chmod 600). Missing files → `verifyFailed`, nothing stored, nothing
  written to `~/.qoder`.
- Session launch seeds the session `.auth` from the provider store. When no
  provider store exists, it copies the machine `.auth` (read-only source).
- `probe()` is ready when the provider store holds both files. The account
  identity (`qodercli status`) is a diagnostic shown by the login dialog, not
  a launch gate.

Multiple provider rows can therefore hold different Qoder accounts at the same
time. Machine login is never mutated.

## Session model

- New personal sessions with `CliTool.qoder` are `acp: true` by default on
  desktop (inferred at create, like Gemini/CodeBuddy).
- Android: ACP not available → session create stays non-ACP and the compose
  surface hides the CLI as unsupported on that target.
- Reconnect trusts the persisted `AppSession.acp`, not a preference.
- `launchArgCandidates` returns only `[executable, '--acp']`; if the process
  exits immediately without an `initialize` response, the CLI is treated as
  unsupported (guards against upstream removing the hidden flag).

### Mixed-team seats

Qoder seats reuse the existing mixed-team ACP path end to end:

- `SessionMemberBinding.acp` is stamped by `stampMemberAcp` with
  `launchesAcpOnly(CliTool.qoder) == true`, so a Qoder member is ACP whenever
  `_memberAcpGates` passes — no new `_requestedMemberAcpSeed` switch arm.
- Gates follow the generic mixed-seat rule: mixed team, member target is
  local or SSH transport, not Android, `AcpCapability` present.
- `shouldAttachMemberAcp` at connect time is the defense-in-depth gate; a
  failed ACP attach does not fall back to PTY for that seat.
- `teammate-bus` reaches the seat through `prepareTeamConnect` staging
  (`<config>/mcp.json`), because `forwardSessionNewMcpServers = false`.
  `AcpHostMcpPermission` keeps only teammate-bus auto-allowed under `ask`.
- Seat chat, wake, and retry delivery use the existing
  `ChatTab.memberAcpRuntimes` mapping; no TeamBus change.
- Native teams never include Qoder (the CLI has no `--team-name` adapter).

## Provider & models

- One built-in provider preset: **Qoder account** (OAuth, no API key). No
  custom OpenAI-compatible provider in v1.
- Model catalog is account-dependent (`--list-models` / ACP
  `models.availableModels`); the provider section renders the ACP list and
  applies selection through `session/set_model`.
- `reasoningEffort` / `thinking` are written to `settings.json` and forwarded
  as launch args when set.
- Mode (`default` / `acceptEdits` / `auto` / `dontAsk` / `yolo`) maps to the
  existing ACP permission surface; v1 uses the `default` mode with
  `session/request_permission`.

## Headless

`capabilities/headless.dart` runs `qodercli -p "<prompt>" --output-format
stream-json`, with `QODER_CONFIG_DIR` pointing at a seeded temp config dir.
Parses the same JSONL event shape used by the Claude-family headless
capability.

## Testing

- Capability unit tests: ACP argv/env, `.auth` seeding, provider `status`
  probe parsing, MCP `mcp.json` merge, hook `settings.json` fragment,
  plugin `enabledPlugins`, prompt `AGENTS.md`, executable name/package.
- Registry test: every `CliTool` registers the required capabilities.
- Launch-policy tests: `willLaunchPersonalAcp` / `AppSession.acp` inference
  for Qoder on desktop vs Android.
- Auth-store tests: provider isolation, machine fallback, never writing to
  `~/.qoder`.
- Mixed-seat tests: `stampMemberAcp` marks Qoder true on local/SSH mixed
  targets and false on Android; `shouldAttachMemberAcp` false when the
  binding is missing; `prepareTeamConnect` stages `teammate-bus` into
  `mcp.json`.
- `test/integration/qoder_acp_local_smoke_test.dart` (tag `integration`):
  real `qodercli --acp` through `productionAcpSpawner` +
  `AcpSessionRuntime`, one prompt turn; skipped when the binary or login is
  absent.

## Risks

- `--acp` is undocumented; an upstream release may drop it. Detection above
  degrades to "unsupported" instead of a broken session.
- `.auth` format is opaque and may change; seeding is file-level and never
  parsed, so a format change only affects login validation.
- `qodercli login` requires a browser; on headless Linux there is no
  device-code flow in 1.1.81.

## Out of scope (follow-ups)

- Native JSONL history parsing (`projects/*.jsonl`)
- `loadSession` / resume via the CLI's own transcript
- Personal sessions on Android / SSH (mixed seats on SSH follow the generic
  mixed-seat gate)
- Custom / BYOK providers
- Qoder private `_meta` (quota model breakdown, prompt queueing)

## Implementation notes (2026-11-03)

Deliberate deviations from the text above, as shipped:

- **Model catalog is live (superseded the static v1 list).**
  `QoderModelsService` runs a short `initialize` + `session/new` ACP probe
  with a provider-seeded config dir, reads
  `models.availableModels[].modelId`, and caches the result per provider for
  six hours (`cache/qoder_models/<provider>.json`). The static list is only a
  fallback for an offline / signed-out probe. Ids are used as-is because
  `session/set_model` rejects the `--list-models` display names (for example
  `qwen3.8-max` fails while `qmodel_38max` works). The probe also caches each
  model's `name`, so pickers and the compose chip show `Qwen3.8-Flash` while
  the persisted value stays `qfmodel` (`ModelDisplayNameCapability`).
- **`reasoningEffort` is a dead write.** The value is merged into
  `settings.json` but is not forwarded as a launch argument, and the effort
  pickers are hidden (`teamPickerPlacement` / `memberPickerPlacement` /
  `providerPickerPlacement` all return `hidden`). Effectively no behavior
  change from the user's perspective until the CLI accepts the setting.
- **Native commands are a hardcoded subset.** Goal / compact / plan / help are
  declared statically rather than driven by ACP `available_commands_update`.
- **Cross-machine seats seed `.auth` through the work-plane manifest.** The
  source (provider store, else the machine `~/.qoder/.auth`) is read on the
  control plane, then both files are copied onto the work plane with
  `copyFilePrivate` so the manifest flushes them to the SSH target with mode
  `0600`. Overlay reads fall through to the control plane, so the remote
  `.qoder-provider` marker is not observable: a cross-machine seat cannot tell
  whether its own copy was refreshed, and **every connect re-copies the current
  control-plane source**. The machine-login fallback itself remains
  control-plane only: a remote host with no seeded copy cannot authenticate
  from its own `~/.qoder`.
- **Session `.auth` is reseeded when the source fingerprint changes.** A
  successful seed writes `<configDir>/.auth/.qoder-provider`
  (`<providerId>:<sha256-12>` of the two source files, or `machine:<hash>` for
  the fallback). Later seeds keep the session copy when the fingerprint matches
  or is absent (legacy/preexisting), so in-session token refreshes survive; a
  re-login or provider switch changes the source bytes, so the fingerprint
  changes and existing sessions are reseeded.
- **Each login attempt starts unauthenticated.** The dialog deletes the
  isolated login `.auth` before spawning `qodercli login`, and Done stays
  disabled until the process exits with a complete `.auth` pair, so a previous
  attempt's files can never be reported as this attempt's success.
