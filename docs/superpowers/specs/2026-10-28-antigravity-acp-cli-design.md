# Antigravity CLI (ACP-only) Design

## Goal

Add **Google Antigravity CLI** (`agy`) as a first-class TeamPilot launchable
CLI. Antigravity is **ACP-only**: chat, permissions, status, history replay,
and usage run through the app-owned ACP stack. There is no PTY / terminal
fallback.

Everything else in the TeamPilot CLI surface is in scope: executable
discovery/install, provider + models, skills, MCP, hooks, plugins, prompt /
rules, native commands, headless one-shot runs, login, usage, and readiness.

Locked decisions (2026-10-28):

- **ACP-only**, no PTY.
- **Desktop local first.** SSH / Android ACP stay out of Phase 1.
- **One-click official adapter download** with pinned version + sha256.
- **Machine Google account** (OS keyring) for authentication. Per-provider
  account isolation is a later phase because the keyring is process/account
  scoped, not `HOME` scoped.
- **Resource isolation via a per-session fake `HOME`.** If the ACP server does
  not honor `HOME`, fall back to namespaced global writes (documented below).

## Evidence

### Official ACP distribution

The ACP Registry entry `antigravity-acp` is published by **Google LLC**
(version **1.4.3** at the time of writing):

| Platform | Archive | Command |
|---|---|---|
| macOS arm64 / x64 | `agy-acp-server-1.4.3-darwin-*.zip` | `./agy_acp_server.par` |
| Linux x86_64 / arm64 | `agy-acp-server-1.4.3-linux-*.zip` | `./agy_acp_server.par --uid=` |
| Windows x64 / arm64 | `agy-acp-server-1.4.3-windows-*.zip` | `./agy_acp_server.exe` |

Every platform archive also contains `localharness_external` (`.exe` on
Windows). It must sit next to `agy_acp_server`; without it every `session/new`
fails with `-32603 Could not find default localharness binary`. Each asset has
a sha256 in `agent.json`; the Linux zip is ~337 MB. Google staff confirmed on
the Antigravity forum that the standalone ACP server is the supported
integration path for ACP clients, not the IDE and not `agy` itself.

Known upstream constraints:

- The server is a PyInstaller onefile. It unpacks on every spawn; cold start is
  ~12–25 s before the first prompt (Linux unpacks ~1.8 GB to a temp dir).
- `session/new` ignores model/mode metadata on older builds. Model changes go
  through `session/set_config_option`, or `AGY_ACP_DEFAULT_MODEL` before spawn.
- Linux arm64 has a reported TCMalloc crash on some kernels.
- Auth is `~/.gemini/antigravity-acp/settings.json` plus the OS keyring
  (`auth.type: oauth-personal` for a personal Google account). `session/new`
  is refused until an auth type is known.
- `--uid` is a google3 privilege-drop flag, **not** an account id. On hosts
  without a `nobody` group, omit it and startup aborts; pass `--uid=` (empty)
  to disable the switch. Never pass a user id.
- `GEMINI_HOME` names the `.gemini` directory itself; it is a stronger
  isolation knob than `HOME`.
- `session/load` and `session/list` are supported (`loadSession: true`,
  `sessionCapabilities.list`). `session/load` replays the transcript.
- `usage_update.used` is the per-turn context delta, not a cumulative total;
  `size` is the model context window.
- The ACP release cadence lags `agy`; treat ACP and CLI versions independently.

### Antigravity CLI facts

- Install: `curl -fsSL https://antigravity.google/cli/install.sh | bash`
  (default binary `~/.local/bin/agy`); PowerShell / CMD equivalents exist.
- Settings: `~/.gemini/antigravity-cli/settings.json`.
- Models: `agy models`; `--model <slug>`, `--effort low|medium|high`.
- Headless: `agy -p --output-format stream-json` with `init` / `step_update` /
  `result` NDJSON events; `--continue`, `--conversation <id>`,
  `--dangerously-skip-permissions`, `--print-timeout`.
- Skills: `~/.gemini/antigravity-cli/skills/` and
  `~/.gemini/config/skills/`; workspace `.agents/skills/`.
- MCP: `~/.gemini/config/mcp_config.json`; workspace `.agents/mcp_config.json`;
  `mcpServers` with `command`/`args`/`env` or `serverUrl` (`url` is accepted).
- Hooks: `~/.gemini/config/hooks.json`; workspace `.agents/hooks.json`; six
  events: `SessionStart`, `PreToolUse`, `PostToolUse`, `PreInvocation`,
  `PostInvocation`, `Stop`; decision values are `allow`, `auto_approve`,
  `deny`, `ask`, `force_ask`, `deny_unless_prior_grant`.
- Plugins: `~/.gemini/antigravity-cli/plugins/<name>/`; global
  `~/.gemini/config/plugins/`; `plugin.json` + optional `skills/`, `agents/`,
  `rules/`, `mcp_config.json`, `hooks.json`.
- Rules / prompt: `~/.gemini/AGENTS.md`, `~/.gemini/GEMINI.md`,
  `~/.gemini/config/rules/*.md`, `~/.gemini/antigravity-cli/rules/*.md`.
- Native transcripts: `<appDataDir>/brain/<conversation-id>/.system_generated/logs/transcript.jsonl`
  where `<appDataDir>` is `~/.gemini/antigravity-cli` for the CLI.

### TeamPilot patterns to reuse

- `CodebuddyCliTool` / `GeminiCliTool` are the ACP-only templates.
- `AcpCapability` + `CliTransportCapability({acp})` + `AcpSettingsCapability` already model
  "separate adapter binary" (Claude / Codex) and "ACP-only" (Gemini / CodeBuddy).
- `AcpAskFullAccessCliLaunchSecurityCapability` provides ACP `ask` / `fullAccess`.
- `NoopCliSessionCapability` + `DefaultCliConfigLayout` provide the session
  shell; Cursor shows how to override `sessionIsolatedHomeRoot`.
- `DefaultSkillCapability`, `DefaultMemberConfigInspection`,
  `UserExtraArgsProvider`, `SharedToolCallResolvers` are reusable.
- `AcpSessionRuntime` / `AcpChatRuntimeCubit` / `acp-transcript.jsonl` are the
  ACP chat stack; `session/load` support must be probed per agent.

## Scope

### In scope (Phase 1)

- `CliTool.antigravity` and `AntigravityCliTool`.
- ACP chat + permissions + status + app-owned transcript.
- `agy` executable discovery and install (local; SSH locate is kept).
- Official `agy_acp_server` download, verification, extraction, update check.
- Provider catalog: official Google account; Gemini API key; ADC.
- Models from `agy models` + static fallback; effort mapping.
- Skills, MCP, hooks, plugins, prompt/rules.
- Headless one-shot + streaming.
- Native commands from ACP.
- Usage from ACP `usage_update` (new ACP usage collector, Antigravity-only in
  Phase 1) and headless.
- Readiness cards, settings, l10n, brand icon.
- Tests + integration smoke.

### Out of scope (documented follow-ups)

- PTY / terminal rendering.
- SSH / Android ACP for Antigravity.
- Per-provider Google account isolation.
- Native `brain/.../transcript.jsonl` history parsing. ACP `session/load` is
  supported and may be enabled in Phase 1; transcript replay must not duplicate
  TeamPilot's stored messages.
- Antigravity native team (TeamBus mixed seats only).
- Antigravity marketplace browsing/installation from TeamPilot's catalog
  beyond projecting already-installed TeamPilot plugin bundles.

## Layering

```text
services/cli/antigravity/
  antigravity_tool.dart
  antigravity_bootstrap_entry.dart
  capabilities/
    acp.dart                     # adapter argv/env/translator, ACP-only marker
    acp_settings.dart            # separate adapter + binary installer
    provider.dart                # oauth-personal / gemini-api-key / ADC
    executable.dart              # agy discovery + installed script
    session.dart                 # fake HOME + config layout
    skill.dart                   # DefaultSkillCapability
    mcp.dart                     # mcp_config.json
    hook_writer.dart             # hooks.json (6 events)
    plugin.dart                  # plugin.json projector
    prompt.dart                  # rules / AGENTS.md
    headless.dart                # agy -p --output-format stream-json
    native_commands.dart
    usage.dart                   # ACP usage log + headless
    history/
      ai_history_capability.dart # stub; native transcript is Phase 2
    tool_call_resolvers.dart     # run_command / view_file / replace_file_content...
  provider/                      # model catalog, presets, login dialog
  provider_presets.dart
```

Shared infrastructure additions:

- `services/cli/registry/installer/acp_adapter_installer.dart` — neutral
  adapter installer interface (npm + binary).
- `services/cli/registry/installer/binary_archive_installer.dart` — download,
  sha256, unzip, chmod, atomic install, versioned directory.
- `services/cli/registry/plugins/antigravity_plugin_projector.dart` — neutral
  bundle → Antigravity `plugin.json` tree.
- `services/acp/acp_usage.dart` — map `usage_update` to a persisted event.

`AntigravityBootstrapEntry` injects `HomeStorage` and the model/credential
sources used by `ProviderCapability.loadFromLiveSources` and the login dialog;
it is wired in `app_shell.dart` through the existing `CliBootstrap` map.

Registration and exhaustive switches:

- `registry/built_in_cli_tools.dart`: register `AntigravityCliTool`; the
  required-capability asserts must pass.
- `models/team_config.dart`: add `antigravity('antigravity')`.
- Exhaustive maps that fail analysis until updated:
  `l10n_extensions.dart#appProviderToolLabel`,
  `widgets/cli/cli_brand_icon.dart`,
  `pages/usage/usage_format.dart`,
  `widgets/app_provider/provider_credential_messages.dart`,
  `widgets/app_provider/provider_credential_action_bar.dart`,
  `services/storage/workspace_cli_cache.dart`.
- `models/hook_event.dart#HookEventCapability.matrix`: add exactly the six
  Antigravity rows; this is the single code-side source of truth.
- `l10n/app_en.arb` + `app_zh.arb`: add `appProviderToolAntigravity` and the
  credential/readiness/session strings.
- Tests that iterate `CliTool.values` (registry, launch-security, skill,
  plugin, history-wiring) are expected to pick up the new value and must pass.

No `if (cli == CliTool.antigravity)` outside the Antigravity directory. Call
sites resolve capabilities through `CliToolRegistry`.

## Capability mapping

| Capability | Implementation | Notes |
|---|---|---|
| `AcpCapability` + `CliTransportCapability({acp})` | `AntigravityAcpCapability` | `agy_acp_server`, no PTY |
| `AcpSettingsCapability` | `AntigravityAcpSettings` | `usesSeparateAdapter: true`, `showsPersonalAcpSwitch: false` |
| `CliExecutableCapability` | `AntigravityExecutableCapability` | `agy`; official install script |
| `CliSessionCapability` | `AntigravityCliSessionCapability` | fake `HOME`; config root |
| `ProviderCapability` | `AntigravityProviderCapability` | account + API key + ADC |
| `SkillCapability` | `DefaultSkillCapability` | `<configDir>/skills` |
| `McpCapability` | `AntigravityMcpCapability` | `<configDir>/mcp_config.json` |
| `HookCapability` | `AntigravityHookWriter` | 6-event `hooks.json` dialect |
| `PluginCapability` | `AntigravityPluginCapability` | `plugin.json` projector |
| `PromptCapability` | `AntigravityPromptCapability` | `<configDir>/rules/teampilot.md` |
| `HeadlessCapability` | `AntigravityHeadlessCapability` | stream-json |
| `AiHistoryCapability` | `AntigravityAiHistoryCapability` | stub + resolvers |
| `NativeCommandCapability` | `AntigravityNativeCommands` | ACP command updates |
| `SessionUsageCapability` | `AntigravitySessionUsageCapability` | ACP usage log |
| `TeamBehaviorCapability` | `AntigravityTeamBehavior` | no native team |
| `ChatInteractionCapability` | `AntigravityChatInteraction` | no structured ask |
| `TerminalBehaviorCapability` | `AntigravityTerminalBehavior` | no PTY |
| `WorkspaceBaseInfoCapability` | `AntigravityWorkspaceBaseInfo` | cwd + prompt extras |
| `MemberConfigInspectionCapability` | `DefaultMemberConfigInspection` | reads projected tree |
| `CliLaunchSecurityCapability` | `AcpAskFullAccessCliLaunchSecurityCapability` | ACP ask/full |
| `InteractiveCliLoginCapability` | `AntigravityProviderCapability` | browser OAuth via `agy` |
| `RuntimeEventCapability` | `AntigravityChatInteraction` | no-op events |

## ACP launch and environment

- `agentExecutable` resolves the installed `agy_acp_server.par` (Windows:
  `agy_acp_server.exe`) first (versioned app-data dir), then `PATH`,
  `~/.local/bin`, and the TeamPilot toolchain.
- `launchArgCandidates`:
  - macOS / Windows: `[[adapter]]`.
  - Linux: `[[adapter, '--uid='], [adapter]]`. `--uid=` is an empty privilege
    drop, not a user id; the probe confirmed that a non-empty value aborts when
    the group does not exist.
- `buildEnvironment`:
  - `HOME` (POSIX) / `USERPROFILE` (Windows) = `<sessionToolDir>/home`.
  - `GEMINI_HOME` = `<sessionToolDir>/home/.gemini` (the stronger isolation
    knob; it points at the `.gemini` directory itself).
  - `AGY_ACP_DEFAULT_MODEL` = selected model slug (unless empty).
  - `GEMINI_API_KEY`, `GOOGLE_GEMINI_BASE_URL` for the API-key provider.
  - `AGY_ADC_AUTH=true`, `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION` for ADC.
- `authenticateMethodId`: `null`; `session/new` uses the pre-seeded
  `auth.type` from `settings.json`. Do **not** call `authenticate` for
  `oauth-personal` in a non-interactive path: it blocks on a browser flow.
  A missing auth type surfaces the server's `-32000 Authentication required`
  message as an actionable sign-in error.
- `forwardSessionNewMcpServers`: `false` initially; MCP is staged in
  `mcp_config.json`. Flip only if the probe shows the server ignores the file.
- `sessionNewMeta`: none.
- Translator: no flags; map abort/`session/cancel` errors to `acpStopCancelled`;
  map auth failures to `acpStopAuthRequired`.
- Add an optional `Duration get startupTimeout => const Duration(seconds: 30)`
  getter to `AcpCapability` (default preserves existing CLIs); Antigravity
  overrides it to **120 s** to cover PyInstaller unpack + `session/new`.
  `AcpConnection.initialize` (currently 15 s) and `AcpConnection.newSession`
  (currently 30 s) already accept a named `timeout`; `AcpSessionRuntime.start`
  passes `cap.startupTimeout` to both. Prompts keep their existing timeout.

## Adapter acquisition and readiness

### Neutral installer interface

Replace the npm-only field:

```dart
abstract interface class AcpAdapterInstaller {
  /// Stable install-job target id. Claude/Codex keep their static
  /// `jobTarget`; this getter avoids the static/instance name collision.
  String get adapterJobTarget;
  String get executableName;
  String get displayName;
  bool get supportsInstaller;
  Future<String?> resolveInstalledPath();
  Future<String?> latestVersion();
  Future<CliInstallResult> install(CliInstallContext context);
}
```

`NpmInstallerCapability` implements it unchanged; `AcpSettingsCapability`
stores `AcpAdapterInstaller? adapterInstaller`.

Update all npm-specific call sites:

- `pages/config/cli_readiness_card.dart`
- `pages/home_workspace/workspace/local_cli_readiness_banner.dart`
- `pages/home_workspace/workspace/remote_cli_machine_readiness_panel.dart`
- `services/remote/remote_cli_readiness.dart`
- `services/remote/remote_preflight_cli_install.dart`
- `services/cli/cli_installer_service.dart`
- `services/install/install_job_keys.dart`
- `services/cli/acp_adapter_discovery.dart`

### Binary installer

`AntigravityAcpAdapterInstaller` uses a pinned release catalog:

```dart
const antigravityAcpRelease = (
  version: '1.4.3',
  assets: {
    'darwin-aarch64': (url: '…', sha256: 'c57d…'),
    'darwin-x86_64': (url: '…', sha256: '9392…'),
    'linux-x86_64': (url: '…', sha256: '0634…'),
    'linux-aarch64': (url: '…', sha256: '05c1…'),
    'windows-x86_64': (url: '…', sha256: '54c2…'),
    'windows-aarch64': (url: '…', sha256: 'fcd4…'),
  },
);
```

Install flow:

1. Resolve platform/arch; unsupported → structured failure.
2. Download to `<appData>/downloads/antigravity-acp-<version>.zip`.
3. Verify sha256 before extraction.
4. Extract with `package:archive`; keep `agy_acp_server(.exe)` **and**
   `localharness_external(.exe)` on every platform.
5. `chmod 755` on Unix for both executables.
6. Atomically move to `<appData>/toolchain/antigravity-acp/<version>/`.
7. Persist `install.json` (`version`, `installedAt`).
8. `resolveInstalledPath()` returns the versioned executable; readiness and
   `AcpAdapterDiscovery` consult it before PATH.

`CliInstallPhase` gains `downloading` and `extracting`; every switch that
labels phases must handle them. Downloads report bytes via `detail` so the
existing install-job progress UI can show a percentage.

`latestVersion()` returns the pinned catalog version in Phase 1. Refreshing the
pin from the ACP Registry at runtime (with checksum verification) is a
follow-up; TeamPilot does not silently install a newer unpinned build.

`install()` rejects `CliInstallMode.ssh` with a clear “remote install not
available yet” result; remote *locate* still works. This keeps the SSH surface
honest until Phase 2.

### `agy` installer

`AntigravityExecutableCapability` implements `CliExecutableCapability` and a
small shared script-install helper:

- Local POSIX: `curl -fsSL https://antigravity.google/cli/install.sh | bash`.
- Local Windows: PowerShell `irm https://antigravity.google/cli/install.ps1 | iex`.
- Termux: reject with a clear message (same guard as Cursor/OpenCode).
- The installer only runs after an explicit user action in the readiness card.
- `defaultExecutableName = 'agy'`, preferences key `cli.antigravity.path`,
  labels from l10n.
- SSH: `install()` returns a structured “remote install not available yet”
  failure. Remote *locate* stays available; remote *install* is Phase 2.

## Config home and authentication

### Fake home

`AntigravityCliSessionCapability` overrides:

- `sessionIsolatedHomeRoot` = `<session runtime tool dir>/home`.
- `sessionConfigDir` = `<home>/.gemini/config` (the global resource root used
  by the typed resource provisioners).
- `prepareSessionIsolatedHome` creates the `home` dir (and a Windows junction
  when needed), same as Cursor.

Resulting paths inside the session:

| Surface | Path |
|---|---|
| Skills | `<configDir>/skills` |
| MCP | `<configDir>/mcp_config.json` |
| Hooks | `<configDir>/hooks.json` |
| Plugins | `<configDir>/plugins/<name>/` |
| Rules / prompt | `<configDir>/rules/teampilot.md` |
| CLI settings | `<home>/.gemini/antigravity-cli/settings.json` |
| ACP settings | `<home>/.gemini/antigravity-acp/settings.json` |
| Headless settings | `<home>/.gemini/antigravity-cli/settings.json`; usage from the stream `result` |

`HOME` / `USERPROFILE` are set by `AntigravityAcpCapability`,
`AntigravityHeadlessCapability`, and `materializeSessionHome`.

### Probe-first fallback

The first implementation task is a probe script that runs the real adapter with
`HOME` pointed at a temp dir and checks whether it reads/writes there. If it
ignores `HOME`:

- Do **not** write the user's real `~/.gemini/config/mcp_config.json` or
  `hooks.json` wholesale.
- Write only TeamPilot-owned artifacts:
  `~/.gemini/config/rules/teampilot.md`,
  `~/.gemini/antigravity-cli/skills/teampilot-*`, and merge MCP/hook entries
  under TeamPilot-owned names; never delete unknown keys.
- Emit a diagnostic (`antigravity_home_isolation_unavailable`) and show a
  warning in readiness.

### Authentication

- Personal Google account: `~/.gemini/antigravity-acp/settings.json` with
  `auth.type = oauth-personal`; token lives in the OS keyring and is shared by
  all sessions.
- `InteractiveCliLoginCapability` opens a terminal dialog running `agy` with
  the isolated home; the user completes the browser flow; **Done** verifies by
  running `agy models` and records readiness.
- Multiple official provider rows share the same keyring account. The UI must
  state this; per-account isolation is out of scope.
- Gemini API key provider writes `modelProvider: gemini` in CLI settings and
  `auth.type: gemini-api-key` in ACP settings; the key is passed as
  `GEMINI_API_KEY` at spawn and never persisted in plain text.
- ADC provider sets `AGY_ADC_AUTH=true` + project/location env; no key is
  stored.

## Provider and models

- Official provider id: `antigravity`; label “Google Antigravity”.
- Catalog sources:
  1. `agy models` (dynamic; parse slug + label lines).
  2. Static fallback from the current docs: `gemini-4-argon-high/medium`,
     `gemini-3.8-flash-high/medium`, `gemini-3.7-flash-high/medium`,
     `gemini-3.6-flash-high/medium`, `gemini-3.1-pro-high`, etc.
- Model picker: slugs; no tiers.
- Effort: `low` / `medium` / `high`, mapped to `--effort` for headless and to
  the ACP config option when the server exposes one.
- ACP model switching: `session/set_config_option` after start; at spawn,
  `AGY_ACP_DEFAULT_MODEL` is the only pre-start lever on builds that ignore
  `session/new` model metadata.
- `materializeSessionHome` writes:
  - `<home>/.gemini/antigravity-cli/settings.json` (`model`, `modelProvider`,
    `permissions` as needed; merge, never clobber user keys),
  - `<home>/.gemini/antigravity-acp/settings.json` (`auth.type`),
  - environment for key/ADC.

## Resources

### Skills

`DefaultSkillCapability` with `skillsSubdir = 'skills'`; because
`<configDir>` is already `<home>/.gemini/config`, skills land at
`<configDir>/skills`. Skills are standard `SKILL.md` folders; no Claude-flavor
projection.

### MCP

`AntigravityMcpCapability.write` uses `mergeMetadataMcpServers` with
`mcp_config.json`. `RemoteMcpServer` `url` is accepted by Antigravity (`url` is
documented as an alias of `serverUrl`). `bearer_token_env_var` is not native;
materialize it as an `Authorization: Bearer` header when needed. Stale
`teampilot` bus entries are removed the same way as CodeBuddy.

### Hooks

New `AntigravityHookWriter` (do not reuse `ClaudeFamilyHookWriter`):

```json
{
  "teampilot-<id>": {
    "PreToolUse": [
      {
        "matcher": "run_command",
        "hooks": [
          {"type": "command", "command": "<script>", "timeout": 10}
        ]
      }
    ]
  }
}
```

- Six native events; add only those keys to `HookEventCapability.matrix`.
- `PreToolUse` / `PostToolUse` support matchers; the other four ignore them.
- Policy decisions use Antigravity's `decision` values:
  `{"decision":"allow"}` / `{"decision":"deny","reason":"…"}`.
  Non-intercepting events ignore `HookPolicy` with a warning.
- `GlueScriptBuilder` is reused with the Antigravity decision JSON and the
  existing timeout/env/script-file contract.
- Native plugin hook actions and HTTP hooks are unsupported (warnings).

### Plugins

`AntigravityPluginCapability`:

- `runtimeOwnership = teamPilot`, `pluginsSubdir = 'plugins'`,
  `pluginsRepresentation = linkedDirectory`,
  `manifestPaths = neutralPluginManifestPaths`.
- `supported = {skills, agents, hooks, mcp, rules}`; `commands` unsupported
  (Antigravity has no plugin command component).
- `provision` copies enabled bundles from the session bundle pool into
  `<configDir>/plugins/<name>/` and projects:
  - neutral `.plugin/plugin.json` → root `plugin.json`,
  - `skills/`, `agents/`, and `rules/` as-is,
  - neutral MCP fragment → `mcp_config.json`,
  - neutral hook fragment → `hooks.json` (Antigravity schema).
- `consumesMarketplaces = true`; shared marketplace materialization is reused.
- No registry JSON file exists; the CLI scans the directory.

### Prompt / rules

`AntigravityPromptCapability` writes `<configDir>/rules/teampilot.md` with the
assembled system prompt. Member role contributions are produced by the existing
`PromptContributionProvider` sources, not embedded by the ACP layer.

## Headless

`AntigravityHeadlessCapability`:

- Args: `agy -p`, `--output-format stream-json` when streaming, `--model`,
  `--effort`, `--dangerously-skip-permissions` (full access), prompt via argv
  or stdin.
- Env: isolated `HOME` / `USERPROFILE` / `GEMINI_HOME`, provider key/ADC.
- `streamResultText`: parse `{"event":"result","result":{...}}` and return
  `result.response`.
- `extractText`: parse the final JSON envelope; otherwise return stdout.
- `provision`: write the same settings as `materializeSessionHome` before the
  run; no native session-home dependency.
- `supportsStreaming = true`; `supportsPromptStdin = true` (stream-json input is
  supported, but Phase 1 uses argv for one-shot runs).

## History and usage

### History

Phase 1 uses the ACP app-owned transcript (`acp-transcript.jsonl` plus the
existing mixed-seat transcript files). `AntigravityAiHistoryCapability` is a
stub:

- `locate => null`, adapter parses to `[]`,
- `sessionEnv` exposes the isolated `HOME`,
- `binding = postCaptured`,
- `tailFallbackPrefix = 'antigravity'`,
- tool call resolvers add Antigravity keys on top of `SharedToolCallResolvers`:
  `run_command`, `view_file`, `write_to_file`, `replace_file_content`,
  `multi_replace_file_content`, `list_dir`, `find_by_name`, `grep_search`,
  `search_web`, `read_url_content`, `invoke_subagent`, `send_message`,
  `manage_task`, `schedule`, `ask_question`, `generate_image`.

Phase 2 parses `~/.gemini/antigravity-cli/brain/<id>/.system_generated/logs/transcript.jsonl`
(`step_index`, `source`, `type`, `status`, `content`, `tool_calls`). ACP
`session/load` is supported and replays the transcript; Phase 1 may use it as
long as replay is treated as authoritative.

### Usage

ACP `usage_update` is parsed by `acpd` but currently dropped by
`AcpSession._mapUpdate`. Add a shared `AcpUsageUpdate` variant and persist each
snapshot to an app-owned `acp-usage.jsonl` (session-scoped). Then:

- `AntigravitySessionUsageCapability.scanUsageSource` reads that log, maps
  `used` into the input/context token field (`used` is a per-turn context
  delta, not a cumulative total), records `size` as the context window, and
  dedupes by session + sequence. `cost` is usually absent; the cost engine must
  not invent output tokens or a cost when the server only reports context.
- Headless runs read `result.usage` directly from the NDJSON stream.
- Phase 1 wires the ACP usage log only for Antigravity. CodeBuddy/Gemini keep
  their native transcript scanners; they can opt into the collector later once
  cross-source dedupe is designed. This avoids double-counting.

## Session and team model

- New personal sessions with `CliTool.antigravity` are `acp: true` by default
  on desktop. The inference already exists via `launchesAcpOnly`
  (`AppSession`, `session_repository`, `session_provisional_builder`).
- Android: ACP is blocked; the CLI is hidden/unsupported there.
- Mixed team: eligible seats attach ACP when the target is local and the CLI
  registers `AcpCapability`; ACP-only forces true.
- `supportsNativeTeam = false`; no `usesClaudeRoster`, no agent presets.
- `defaultForceWaitBeforeStop = false`, `requiresPtyFallback = false`.
- `ChatInteractionCapability`: no structured ask, no in-chat permission reply
  (ACP permission UI handles it); `RuntimeEventCapability` is a no-op.
- `TerminalBehaviorCapability`: turn interrupt handled by ACP cancel; PTY-only
  fields use safe defaults (`supportsTurnInterrupt = false`,
  `usesFullScreenInput = false`).
- `WorkspaceBaseInfoCapability`: ACP `cwd` is the primary workspace; additional
  directories are described in the prompt (the ACP client does not forward
  `additionalDirectories`).

## Error handling and timeouts

| Condition | Behavior |
|---|---|
| `agy` missing | Readiness row with Install; launch blocked with `cliMissing` |
| Adapter missing | Readiness row with Download; launch blocked with `acpLaunchFailedAdapter` |
| Download / sha256 failure | Structured install failure; partial file removed; retry allowed |
| Auth required | `acpStopAuthRequired`; prompt to run Sign in |
| Cold start | ACP launch timeout for Antigravity raised to 120 s; UI shows “Starting Antigravity” |
| Linux arm64 TCMalloc crash | Surface stderr + suggested workaround; no silent retry |
| `--uid` rejected | Fall back to the no-flag candidate; never pass a user id |
| Model rejected | Surface the server error; do not silently switch models |
| `session/load` replay | Treat the server replay as authoritative; do not duplicate stored messages |

## Testing

- Capability unit tests:
  - ACP argv/env, `--uid` candidates, HOME isolation, model env, auth type.
  - `mcp_config.json` merge, including `url`/`serverUrl`.
  - `hooks.json` render for all six events + unsupported-event warnings.
  - plugin projection (`.plugin` → `plugin.json`, MCP/hook fragments).
  - headless argv + `result` parsing.
  - `agy models` parsing and static fallback.
- Registry tests:
  - `CliTool.antigravity` registers every required capability.
  - `CliTransportCapability({acp})` present; `AcpSettingsCapability(usesSeparateAdapter: true,
    showsPersonalAcpSwitch: false)`.
  - `launchesAcpOnly(CliTool.antigravity)` true.
  - Tool-call resolvers non-null.
  - `HookEventCapability` has exactly the six native events.
- Installer tests:
  - platform/arch selection, sha256 verify, zip extraction, atomic move,
    versioned path, failure cleanup.
  - readiness card chooses the binary installer, not npm.
- Session tests:
  - personal desktop ACP inference; Android blocked; mixed-seat gate.
- Integration smoke (`@Tags(['integration'])`):
  - real `agy_acp_server`: `initialize` → `session/new` → one prompt; skipped
    when the binary or auth is absent.
  - real `agy -p` headless one-shot; skipped when absent.
- Verification: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
  and `dart run tool/run_tests.dart` (never bare `flutter test`).

## Documentation and l10n

- Add `docs/cli-formats/antigravity.md` (tool names, transcript, usage).
- Update `docs/cli-formats/README.md`, `tool-layer-coverage.md` (move out of
  pre-research), and `docs/cli-formats/hooks.md` (six-event row).
- Update `docs/cli-architecture.md` (CLI list + capability table) and
  `docs/ARCHITECTURE.md` if ACP-only CLIs are enumerated.
- l10n: `appProviderToolAntigravity` + credential/session/readiness strings in
  `app_en.arb` and `app_zh.arb`.
- Brand icon: add `antigravity` to `cli_brand_icon.dart`, the generated provider
  icon catalog, and an SVG asset; if the official mark is unavailable, use the
  Google “G” fallback mark and track the brand asset as a follow-up.

## Probe-first tasks (first implementation step)

These are the first implementation tasks, not placeholders. Each produces a
recorded result in the implementation plan / PR description:

1. Run `agy_acp_server` with `HOME` isolated; verify it reads/writes there,
   and whether it needs `--uid`.
2. Send `initialize`; record `agentInfo`, `authMethods`, and whether
   `authenticate` is required.
3. Send `session/new`; record config options, model handling, MCP behavior,
   and whether `session/load` / `session/list` exist.
4. Run one prompt; record `usage_update` shape and `session/cancel` behavior.
5. Verify `agy models` and `agy -p --output-format stream-json` with an
   isolated home.
6. Verify a TeamPilot plugin bundle projected to `plugin.json` is loaded by
   the CLI (`/plugin list` or `/skills`).
7. Verify Antigravity hook `decision` JSON with a `PreToolUse` allow/deny pair.

The fallback for 1 is the namespaced-global strategy above; the fallback for 3
is `forwardSessionNewMcpServers = true`; the fallback for 5 is the static model
list; the fallback for 6 is to mark plugins unsupported and keep the rest.

## Definition of done

- `flutter analyze` clean and the full test suite green.
- Integration smoke passes locally with a signed-in Antigravity account.
- No `if (cli == CliTool.antigravity)` outside `services/cli/antigravity/`.
- Readiness card installs `agy` and the adapter; a missing adapter is detected
  before launch.
- A personal desktop session runs ACP chat end-to-end, with usage recorded.
- Skills, MCP, hooks, plugins, rules, and headless are exercised by tests.
- Docs and l10n updated.
