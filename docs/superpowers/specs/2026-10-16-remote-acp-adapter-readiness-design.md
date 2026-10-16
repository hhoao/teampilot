# Remote ACP Adapter Readiness Design

> Follow-up (separate spec / plan): **spec (b)** — run mixed-team *remote*
> seats as ACP. It needs the `_memberAcpGates` local-only restriction relaxed,
> remote TeamBus MCP reachability, and SSH reconnect. This spec is **spec (a)**
> and is its prerequisite.

## Goal

Make a terminal-less ACP session that targets an **SSH work machine** work
end-to-end for the CLIs whose ACP needs a **separate adapter binary** (Claude
`claude-agent-acp`, Codex `codex-acp`):

1. **Detect** the adapter on the remote host before launch, so a missing
   adapter is surfaced the same way a missing CLI is today.
2. **Prompt + install** on that host from the compose landing panel (the
   `RemoteCliMachineReadinessPanel` that already appears "below" the compose
   card for a missing remote CLI) and from Settings.
3. **Locate + use** an absolute remote adapter path at launch, symmetric with
   the existing per-target CLI path override, instead of relying on the bare
   adapter name resolving through a possibly-sparse non-interactive PATH.

## Why

Remote personal ACP already exists (Phase 1, merge `5dce25bd4`): personal
Claude/Cursor/Codex/OpenCode sessions on `RuntimeKind.ssh` targets spawn the
agent over an SSH exec channel (`AcpSshTransport` + `DartSsh2AcpChannel`) and
stage remote CLI path / env / config dirs through the PTY staging path
(`SessionConnectOrchestrator.prepareSimpleConnect`).

What Phase 1 deliberately left out (`docs/superpowers/plans/2026-10-15-acp-ssh-transport.md`,
"Scope And Assumptions"):

- "Remote adapter install/locate for Claude/Codex ... is follow-up work."
- "Adapter install jobs stay local-only. No SSH adapter discovery."

Consequences today:

- **Landing**: `WorkspaceLandingLaunchGate.asyncRemoteCliBlockForSimple` →
  `remoteCliRequirementsForSimpleLaunch` builds a `RemoteCliRequirement` for the
  **CLI only**; `RemoteCliReadinessService.probe` only knows `CliTool`. So a
  remote host with `claude` but no `claude-agent-acp` shows **no panel**, and
  the launch fails at spawn (`acpLaunchFailedAdapter`, see
  `AcpSessionRuntime.start`).
- **Settings**: `CliReadinessCard` gates the adapter Install button on
  `cubit.hasKnownAcpAdapter(cli)`, which comes from **local** boot discovery
  (`AcpAdapterDiscovery.locateLocal()`); `_locateAdapter` is local-only; the
  adapter install job (`InstallJobKeys.claudeAcpAdapter()` /
  `codexAcpAdapter()`) has **no scope**, so it is always local. Meanwhile the
  CLI install in the same card uses `installJobScopeForContext(context)`, which
  resolves to `InstallJobScopeSsh(profileId)` in the remote work plane — hence
  "CLI prompts to install, ACP does not."

The machinery to install an adapter remotely already exists and is unused:
`CliInstallerService.installAdapter(mode: CliInstallMode.ssh, sshProfile: …)`
and `CliInstallJobRunner` (which already maps adapter job targets and resolves
`InstallJobScopeSsh`). This spec wires the missing readiness + path override.

## Decisions Locked With The User

- **Path override (approach A)**: add a per-target adapter path override to
  `targets.json` and inject the absolute path at launch. Rejected approach B
  (rely on bare-name PATH resolution only) because remote `ssh exec` is a
  non-interactive shell whose PATH may be minimal, so an adapter located
  outside `$PATH` / `~/.local/bin` / the TeamPilot node prefix would "Locate"
  successfully yet still fail to spawn.
- **No auto-install**: connect only locates; installing is always user-driven
  from the landing panel or Settings (mirrors the CLI policy).
- **Missing remote adapter blocks the launch**, exactly like a missing remote
  CLI (`RemoteCliMissingLaunchBlock`).
- **Only CLIs with `AcpSettingsCapability.usesSeparateAdapter == true`** (Claude,
  Codex) produce an adapter requirement. Cursor / OpenCode / Gemini reuse the
  CLI binary; Gemini personal-desktop is always ACP but needs no adapter.
- **Mixed-team remote seats stay out of scope** (spec (b)).
- **Android / Termux unchanged**: `resolveLaunchAcp` returns false on Android,
  so no ACP remote there.

## Scope

**In scope**

- Remote adapter detection for personal (simple) ACP launches.
- Landing gate + `RemoteCliMachineReadinessPanel` adapter row and remote install.
- Settings `CliReadinessCard` adapter row in the remote work plane (probe the
  selected profile, remote install with SSH scope, remote locate).
- Per-target adapter path override in `targets.json`, remembered after
  locate/install, injected at ACP launch.
- l10n copy for the adapter rows.
- Tests + a documented real-machine smoke checklist.

**Out of scope**

- Mixed-team remote ACP seats (spec (b)).
- Remote adapter version probe / upgrade ("Update available" stays CLI-only on
  remote; there is no remote `--version` probe today).
- Remote adapter auto-install.
- Adapter install for Cursor / OpenCode / Gemini (no separate adapter).

## Architecture

"adapter" becomes a first-class peer of "CLI" across the remote-readiness
pipeline. Every stage that today keys off `(target, CliTool)` gains an explicit
`CliBinaryKind` dimension (`enum CliBinaryKind { cli, adapter }`, already in
`client/lib/models/cli_binary_kind.dart`).

### Components

| Unit | Responsibility | Change |
|------|----------------|--------|
| `RemoteCliRequirement` (`client/lib/services/remote/remote_cli_requirements.dart`) | One required remote binary for one host | Add `final CliBinaryKind kind` (default `cli`); `cacheKey` becomes `targetId\|kind.name\|cliValue` |
| `remoteCliRequirementsForSimpleLaunch` | Required remote binaries for a simple launch | Add `required bool requestedAcp`; append an adapter requirement when `requestedAcp && AcpSettingsCapability.usesSeparateAdapter` |
| `WorkspaceLandingLaunchGate.asyncRemoteCliBlockForSimple` (`client/lib/services/chat/launch/pre_send/workspace_landing_launch_gate.dart`) | Probe required binaries | Forward `requestedAcp`; probe/report adapter requirements unchanged otherwise |
| `RemoteCliReadinessService` (`client/lib/services/remote/remote_cli_readiness.dart`) | Locate / install one remote binary | `probe`/`install` take `CliBinaryKind kind = CliBinaryKind.cli`; adapter branch locates via `AcpAdapterDiscovery.locateRemote`, requires `AcpSettingsCapability.adapterInstaller != null`, installs via `buildRemotePreflightAdapterInstall`, and reads/writes the adapter override |
| `AcpAdapterDiscovery` (`client/lib/services/cli/acp_adapter_discovery.dart`) | Locate adapters | Add `locateRemote({required SshCommandRunner run})` using `DefaultRemoteCliLocator(adapterExecutableName)` per separate-adapter CLI |
| `buildRemotePreflightAdapterInstall` (`client/lib/services/remote/remote_preflight_cli_install.dart`) | Remote install `RemoteInstallAction` | New adapter twin of `buildRemotePreflightCliInstall`, calling `CliInstallerService.installAdapter(mode: ssh, …)` |
| `InstallJobKeys` (`client/lib/services/install/install_job_keys.dart`) | Job identity | `claudeAcpAdapter({required InstallJobScope scope})`, `codexAcpAdapter({required InstallJobScope scope})` |
| `InstallJobEnqueue` (`client/lib/services/install/install_job_enqueue.dart`) | Enqueue helpers (Settings) | `installClaudeAcpAdapter` / `installCodexAcpAdapter` gain `required InstallJobScope scope` |
| `CliInstallJobRunner` (`client/lib/services/install/runners/cli_install_job_runner.dart`) | Job runner | Unchanged: already supports adapter targets and SSH scope |
| `TargetsRegistryFile` / `TargetsRepository` (`client/lib/services/storage/targets_repository.dart`) | Control-plane storage | Add `acpAdapterPathOverrides` (`targetId → {cliValue → path}`) + `acpAdapterPathOverride` / `setAcpAdapterPathOverride` |
| `remember_remote_cli_path.dart` (`client/lib/services/remote/`) | Path cache | Add `rememberRemoteAcpAdapterPathIfNeeded(...)` |
| `RemoteCliMachineReadinessPanel` (`client/lib/pages/home_workspace/workspace/remote_cli_machine_readiness_panel.dart`) | Per-host readiness UI | Render adapter rows; for an adapter requirement build a scoped adapter `InstallJobSpec` (as it already does for CLI) whose `run` calls `RemoteCliReadinessService.install(kind: adapter)` |
| `CliReadinessCard` (`client/lib/pages/config/cli_readiness_card.dart`) | Settings readiness | In remote work plane: adapter knownness from override/probe, `_locateAdapter` remote, install with SSH scope |
| `AcpRuntimeAttach` (`client/lib/services/chat/launch/connect/acp_runtime_attach.dart`) | ACP attach | Resolve the remote adapter override for the launch target and pass it as `discoveredAdapterPath` |
| `SessionLaunchHost` (`client/lib/services/chat/launch/session_launch_host.dart`) | Injection seam | New async remote-adapter-path resolver getter (null in tests) |

### Data flow — landing (personal remote ACP)

```
compose draft (personal + cli + ACP requested)
  └─ WorkspaceLandingLaunchGate.asyncRemoteCliBlockForSimple(requestedAcp)
       └─ remoteCliRequirementsForSimpleLaunch
            → [ requirement(kind: cli, cli: claude),
                requirement(kind: adapter, cli: claude) ]   # when requestedAcp && separate adapter
       └─ RemoteCliReadinessService.probe(kind) per requirement
            cli     → CliExecutableCapability.locateRemote
            adapter → AcpAdapterDiscovery.locateRemote (DefaultRemoteCliLocator(adapterName))
       └─ missing → RemoteCliMissingLaunchBlock([...]) → RemoteCliMachineReadinessPanel
            install (panel)    → readiness.install(kind: adapter)
                 → buildRemotePreflightAdapterInstall → CliInstallerService.installAdapter(mode: ssh)
            install (settings) → installClaudeAcpAdapter(scope) → CliInstallJobRunner → installAdapter
            success → paths remembered into targets.json overrides
```

### Data flow — launch injection

```
AcpRuntimeAttach.attachAcpRuntime (remote branch)
  ├─ staging → executable / sessionToolDir / baseEnv        (existing)
  ├─ remoteAdapterPath = host.remoteAcpAdapterPath(target.id, cli)   # NEW
  └─ AcpChatRuntimeCubit.start
       └─ AcpSessionRuntime.start → launchPlan.buildEnvironment
            └─ plan.agentExecutable(cliExecutable)
                 discoveredAdapterPath: absolute override wins, else bare adapter name
       └─ spawner → AcpSshTransport (existing)
```

## Storage

`targets.json` (control plane, written by `TargetsRepository`) gains:

```json
{
  "schemaVersion": 1,
  "acpAdapterPathOverrides": {
    "<targetId>": { "claude": "/home/u/.local/bin/claude-agent-acp" }
  }
}
```

- Keyed `targetId → cliValue → absolute path`; empty path removes the entry
  (same semantics as `cliPathOverrides`).
- Omitted from JSON when empty (backward compatible; no schema-version bump —
  unknown keys are already ignored on read).
- Never stored on the home plane when the target is remote; the map is keyed by
  target id and holds remote paths only.

## UI

### Landing panel

- Adds one row per adapter requirement, next to the CLI row: brand icon + "ACP
  adapter" label + the host label, with the same probe/Installing/Failed states.
- Install action enqueues the **scoped** adapter install job and re-probes on
  success.
- The existing "install hint" footer covers adapter rows unchanged.

### Settings card (remote work plane only)

- The ACP row's knownness comes from the per-target override (and a remote probe
  on first frame) instead of local boot discovery.
- `Locate` runs the remote adapter probe against the currently selected SSH
  profile and writes the override; `Browse` stays disabled (cannot pick a remote
  file), matching the CLI row.
- `Install` enqueues the scoped adapter install job. `Upgrade` stays hidden on
  remote (no remote version probe).
- Local (non-remote) behavior is unchanged.

## Error Handling

- Missing adapter and failed adapter probe both block the launch with
  `RemoteCliMissingLaunchBlock` — the same path a missing CLI already takes.
- Install failures surface the existing `RemoteCliFailed.message`
  (`remoteCliFailureMessage`) in the panel row and install-job history.
- A null/empty remote adapter override is not an error: launch falls back to the
  bare adapter name (current behavior), preserving the existing
  `acpLaunchFailedAdapter` failure key if the adapter is genuinely absent.
- Unknown SSH profile for a target fails the same way the CLI/service paths
  already do (`StateError('No SSH profile for target …')`).

## Testing

Unit / widget (no real sshd):

- `remoteCliRequirementsForSimpleLaunch` emits a `kind: adapter` requirement iff
  `requestedAcp && usesSeparateAdapter`; `cacheKey` disambiguates cli vs adapter.
- `WorkspaceLandingLaunchGate.asyncRemoteCliBlockForSimple` blocks when the
  adapter probe is missing/failed and passes when ready.
- `RemoteCliReadinessService.probe/install(kind: adapter)` with a fake
  `SshCommandRunner`: locates via the adapter name, installs via
  `installAdapter`, writes the adapter override.
- `AcpAdapterDiscovery.locateRemote` maps only separate-adapter CLIs.
- `TargetsRepository` round-trips `acpAdapterPathOverrides` and clears empty
  entries.
- `InstallJobKeys`/`InstallJobEnqueue` scoped adapter keys resolve to distinct
  jobs per profile and the runner resolves SSH scope.
- `RemoteCliMachineReadinessPanel` renders and installs an adapter requirement.
- `CliReadinessCard` remote mode: adapter known from override, locate writes the
  override, install uses SSH scope.
- `AcpRuntimeAttach`: a remote target with an adapter override passes the
  absolute path into the launch plan; absent override falls back to the bare
  name.

Real-machine smoke (manual, documented in the plan — this is the answer to "will
it actually work like PTY"):

1. Remote host has the CLI but not the adapter; personal Claude ACP launch shows
   the panel and installs `claude-agent-acp` on the host.
2. After install, a personal Claude ACP session on the SSH target completes the
   ACP handshake, answers the first prompt, and runs one tool call — for both
   **Official OAuth** and **API-key** credential modes.
3. Repeat with Codex / `codex-acp`.
4. Confirm the resolved adapter path is remembered in `targets.json` and reused
   on the next launch (kill the SSH session between runs).

Known risk to check explicitly in the smoke pass: the Claude ACP env builder
(`ClaudeAcpCapability.buildEnvironment`) overlays the local provider auth on top
of the staged remote env; official mode depends on the staged `.credentials.json`
reaching the **remote** `CLAUDE_CONFIG_DIR`. If that link does not materialize
remotely, official mode will report "Not logged in" even though the local run
works — the smoke pass must catch that before we call this done.

Optional: an `@Tags(['integration'])` end-to-end test that only runs where a
real sshd fixture is available.

## Risks

- **Remote credential linkage for official OAuth** (above) — highest-risk
  unknown; verified by the smoke checklist, not by unit tests.
- **`CliReadinessCard` is local-oriented**: adding async remote probe state to
  the card must not regress the local/Android paths or the boot-discovery
  behavior. Keep the remote branch strictly additive and feature-flag it on
  `ConnectionModeService.isRemoteWorkPlane`.
- **Panel reuse**: `RemoteCliRequirement` is also consumed by the mixed
  placement panel and the team-settings dialog. Adding `kind` with a `cli`
  default keeps those call sites behavior-identical (they only ever build CLI
  requirements today).
