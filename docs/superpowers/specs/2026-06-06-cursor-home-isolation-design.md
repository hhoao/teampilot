# Cursor Mixed-Mode HOME Isolation · Provider Auth · Native `.cursor` Bus Overlay

Date: 2026-06-06  
Status: Approved (design)

## Background / Motivation

TeamPilot mixed-mode Cursor members currently wire the team bus via `--plugin-dir`
(`.cursor-plugin/plugin.json` + `rules/` + `hooks/hooks.json`). **Cursor CLI has a
bug: plugin `rules` do not apply.** Member identity and bus wiring therefore fail
in production.

User testing confirms that overriding `HOME` makes `cursor-agent` read config from
`$HOME/.cursor/` (native layout) and requires a **separate login per isolated HOME**.
That behavior is desirable: Cursor accounts become first-class **providers** (like
Claude/Codex), with per-member isolation at launch.

This spec replaces the plugin-dir path for **mixed mode only**. Standalone Cursor
sessions keep the existing `CURSOR_CONFIG_DIR` + route-B positional prompt.

## Goals

1. Mixed-mode Cursor: isolate each member under a dedicated fake `HOME` with native
   `~/.cursor/` files (rules, hooks, mcp, cli-config).
2. Full Cursor **provider** stack: catalog, team/member binding, interactive login,
   manual import, credential probe, launch-time auth provision.
3. Work on **native PTY, WSL, and SSH** transports (same env contract everywhere).
4. **No legacy code**: delete plugin-dir relay, `CursorTeamBusPlugin`, and all
   `cursorPluginDir` plumbing after migration.

## Non-Goals

- Changing standalone (non-mixed) Cursor launch semantics.
- Injecting real `~/.ssh` / git identity into fake HOME (agent shell tools run under
  isolated HOME; acceptable for mixed bus workflows in v1).
- Cursor IDE integration (CLI only).
- Backward compatibility with old mixed sessions using `--plugin-dir` (users recreate
  team sessions after upgrade).

## Decision Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Isolation root | `HOME` only (mixed) | Matches observed Cursor behavior; one variable across PTY/WSL/SSH |
| Config layout | Native `$HOME/.cursor/` | Rules/hooks/mcp load reliably; not plugin layout |
| Provider store | `providers/cursor/{id}/home/` | Mirrors “fake HOME root”; auth snapshot lives at `home/.cursor/` |
| Member runtime | `…/members/…/cursor/home/` | Same shape as provider store; provision copies auth + writes bus overlay |
| Auth provision | Copy auth artifacts (symlink → copy fallback) | Same pattern as Claude `ensureLinked`; works on SFTP/SSH FS |
| Plugin-dir path | **Removed** | Buggy; no dual-path period |

---

## Architecture

### Module boundaries

```
services/provider/cursor/
├── cursor_home_layout.dart          # Path constants: .cursor/, rules/, hooks.json, …
├── cursor_auth_artifacts.dart       # Auth vs bus vs default file sets (extensible)
├── cursor_home_bus_overlay.dart     # Pure builders: role.mdc, hooks.json, mcp.json, idle.sh
├── cursor_home_provisioner.dart     # Merge provider auth → member home + bus overlay
├── cursor_launch_environment.dart   # HOME / USERPROFILE (+ WSL normalize)
├── cursor_provider_settings_resolver.dart
└── cursor_provider_credentials_service.dart

services/cli/registry/config_profile/
└── cursor_config_profile_capability.dart   # Orchestrates mixed vs standalone branches
```

**Deleted (no re-exports, no deprecation shims):**

- `cursor_team_bus_plugin.dart`
- `TEAMPILOT_CURSOR_PLUGIN_DIR` / `pluginDirEnvKey`
- `CliLaunchContext.cursorPluginDir`
- `LaunchCommandBuilder.cursorPluginDirFromEnvironment` and `_launchOnlyEnvKeys` entry
- `terminal_session.dart` cursorPluginDir extraction
- Mixed-mode `--plugin-dir` / `--approve-mcps` in `CursorCliToolAdapter`
- `test/.../cursor_team_bus_plugin_test.dart` → replaced by overlay + provisioner tests

### Directory layout

```
{teampilotRoot}/
├── providers/cursor/
│   ├── providers.json
│   └── {providerId}/
│       └── home/                    # Provider staging HOME (login/import target)
│           └── .cursor/             # Auth snapshot after login or import
│               ├── cli-config.json
│               └── …                # See cursor_auth_artifacts.dart (discovered in Task 0)
│
└── config-profiles/teams/{teamId}/members/{cliTeamName}/{memberId}/cursor/
    └── home/                        # Member launch HOME
        └── .cursor/
            ├── cli-config.json      # Merged: provider auth + default permissions
            ├── rules/role.mdc       # Member identity (alwaysApply)
            ├── hooks.json           # Native path (NOT hooks/hooks.json)
            ├── hooks/idle.sh
            └── mcp.json             # teammate-bus MCP server
```

### Native vs old plugin layout

| Concern | Old (plugin-dir) | New (HOME / native) |
|---------|------------------|---------------------|
| Rules | `plugin/rules/*.mdc` via manifest | `$HOME/.cursor/rules/*.mdc` |
| Hooks config | `plugin/hooks/hooks.json` | `$HOME/.cursor/hooks.json` |
| Hook scripts | `plugin/hooks/idle.sh` | `$HOME/.cursor/hooks/idle.sh` |
| MCP | manifest `mcpServers` | `$HOME/.cursor/mcp.json` |
| Auth | Global keychain (comment) | `$HOME/.cursor/` per provider |

---

## Mixed launch flow

```
ConfigProfileService.prepareTeamLaunch
  → CursorConfigProfileCapability.contributeLaunch (mixed)
      1. memberHome = memberToolDir/…/cursor/home
      2. provider = CursorProviderSettingsResolver.resolveForLaunch(team, member)
      3. CursorHomeProvisioner.provision(
           memberHome, provider, member, busPort, teamFlags)
      4. environment = CursorLaunchEnvironment.forMixed(memberHome, platform)
      5. warnings if provider/credentials/bus port missing

SessionLifecycleService.prepareLaunch
  → memberConfigDir includes memberHome (for cleanup/probes)

TerminalSession.connect
  → buildPtyEnvironment merges HOME
  → CursorCliToolAdapter: no plugin-dir; no positional prompt in mixed

SSH: SshPtyTransport.buildSessionCommand prepends export HOME=…
WSL: normalizePathForCli on HOME path
Windows: USERPROFILE = memberHome (same path string TeamPilot uses locally)
```

### Environment contract (`CursorLaunchEnvironment`)

```dart
// Mixed mode only
{
  'HOME': memberHome,           // WSL-normalized when needed
  'USERPROFILE': memberHome,    // Windows native + WSL interop
}
```

Standalone mode unchanged:

```dart
{ 'CURSOR_CONFIG_DIR': cursorDir }
```

---

## Provider & credentials

### Resolver priority (same as Codex)

1. `member.provider` → provider id if valid cursor provider  
2. `team.providerIdsByTool['cursor']`  
3. Single cursor provider in catalog (auto-pick)  
4. `null` → warning `cursor_provider_missing`

### `CursorProviderCredentialsService`

Mirrors `ClaudeProviderCredentialsService` responsibilities:

| Method | Behavior |
|--------|----------|
| `providerHome(providerId)` | `{base}/providers/cursor/{id}/home` |
| `probe(providerId)` | Ready if all `CursorAuthArtifacts.required` exist under `home/.cursor/` |
| `runAuthLogin(providerId)` | `HOME=providerHome cursor-agent login` (subcommand confirmed Task 0) |
| `importFromGlobal(providerId, homeDirectory)` | Copy auth artifacts from `{homeDirectory}/.cursor/` |
| `importFromDirectory(providerId, sourceCursorDir)` | Copy from user-selected `.cursor` tree |
| `revokeCredentials(providerId)` | Delete auth artifacts; optional logout with isolated HOME |
| `syncAuthToMemberHome(providerHome, memberHome)` | Symlink/copy auth files into member tree before bus overlay |

### UI (Providers + Team)

- `appProviderPresetsFor(CliTool.cursor)`: at least one “Cursor Account” preset.
- Provider form: name, notes; credential actions (login / import / revoke / status).
- `team_tool_provider_selectors.dart`: enable cursor tool selector.
- `AppProviderCubit`: cursor credential methods (parallel to Claude).
- `app_provider_repository.dart`: cursor case writes provider dirs (no stale cleanup
  logic required v1 beyond delete provider).

### Warnings

| Key | When |
|-----|------|
| `cursor_provider_missing` | No provider resolved |
| `cursor_credentials_missing` | Provider resolved but probe not ready |
| `cursor_bus_idle_url_missing` | Mixed bus port absent |

---

## `CursorHomeProvisioner`

```dart
Future<void> provision({
  required String memberHome,
  required AppProviderConfig? provider,
  required TeamMemberConfig member,
  required int? busPort,
  required bool forceTeamLeadDelegateMode,
}) async
```

Steps:

1. `ensureDir(memberHome/.cursor/…)`
2. If provider != null && probe ready → `syncAuthToMemberHome`
3. Else skip auth (warning already emitted upstream)
4. Write bus overlay via `CursorHomeBusOverlay` (always overwrites bus files):
   - `rules/role.mdc`
   - `hooks.json` + `hooks/idle.sh`
   - `mcp.json`
5. Merge `cli-config.json` defaults (permissions allow bus MCP tools) without
   clobbering auth fields copied from provider

---

## Transport notes

| Transport | Mechanism |
|-----------|-----------|
| Local PTY | `TerminalSession.buildPtyEnvironment` |
| WSL | `normalizePathForCli(memberHome, useWslPaths: true)` |
| SSH | `export HOME='…'` in `SshPtyTransport.buildSessionCommand` |
| macOS external terminal | Existing inline `export` in `LaunchCommandBuilder.launch` |

Provider **login** on SSH: open embedded PTY (or external on desktop) on the SSH
filesystem with `HOME=providers/cursor/{id}/home` so OAuth completes on the remote
host where `cursor-agent` runs.

---

## Testing

| Layer | Coverage |
|-------|----------|
| `cursor_home_bus_overlay_test.dart` | hooks.json schema, mcp.json, role.mdc frontmatter, idle.sh |
| `cursor_home_provisioner_test.dart` | auth copy + bus files land under member home |
| `cursor_launch_environment_test.dart` | HOME/USERPROFILE, WSL path |
| `cursor_provider_credentials_service_test.dart` | import, probe, login env |
| `cursor_cli_tool_adapter_test.dart` | mixed: no `--plugin-dir`; standalone unchanged |
| `cursor_config_profile_capability_test.dart` | mixed emits HOME; standalone emits CURSOR_CONFIG_DIR |

Manual golden path (document in plan): mixed cursor team on Linux PTY, WSL, SSH —
verify rule text in agent behavior, MCP `wait_for_message`, stop hook POST `/idle`.

---

## Auth artifact discovery (implementation Task 0)

Before coding provision logic, run isolated `cursor-agent login` and document exact
auth files in `cursor_auth_artifacts.dart`:

```dart
abstract final class CursorAuthArtifacts {
  static const required = <String>[
    // filled after discovery, e.g. 'cli-config.json', …
  ];
  static const busGenerated = <String>[
    'rules/role.mdc',
    'hooks.json',
    'hooks/idle.sh',
    'mcp.json',
  ];
}
```

`probe()` checks `required`; `syncAuthToMemberHome` copies only `required` (+ any
`optional` token sidecars), never bus-generated paths.

---

## Migration

- No data migration. Existing mixed cursor sessions: user creates new team session.
- Remove dead code in the same PR series as new modules (no feature flag).
