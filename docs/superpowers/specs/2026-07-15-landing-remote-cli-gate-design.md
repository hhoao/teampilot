# Landing Machines remote CLI gate + user-driven install

**Status:** Approved  
**Date:** 2026-07-15

## Problem

Connect-time auto-install of remote Node/CLI blocks members silently and surprises users. Installation must be an explicit user action in the Machines placement UI; launch must refuse to start when a required remote CLI is missing.

## Decisions

1. **Machines panel** is the install surface: per SSH host, show required CLIs (from placed members’ `memberLaunchCli`), locate status, and an **Install** button with `CliInstallProgressPanel`.
2. **Landing launch gate** blocks submit when any SSH-placed member needs a CLI that is not located (override path or remote locate).
3. **Connect path never auto-installs.** `WorkspaceProvisioner._ensureCli` locate-only; missing CLI → clear error (no `RemoteCliInstaller.ensure` install branch on the hot path).
4. **No backward compatibility** with connect-time auto-install or launch-time install progress as the primary UX. Remove auto-install wiring; provision progress overlay may remain only for non-install remote sync if still needed, or be simplified to errors.

## Architecture

```
Machines panel
  → RemoteCliReadinessService.probe(target, requiredClis)
  → RemoteCliInstaller.ensure / buildRemotePreflightCliInstall (user Install only)
  → TargetsRepository.setCliPathOverride (remember path)

Landing submit
  → WorkspaceLandingLaunchGate (+ RemoteCliMissingLaunchBlock)
  → async probe using same readiness service

Connect
  → WorkspaceProvisioner._ensureCli: locate + override only
  → fail fast if missing
```

## Key types

- `RemoteCliReadiness` — per `(targetId, cli)`: `unknown | probing | ready(path) | missing | installing | failed(message)`
- `RemoteCliMissingLaunchBlock` — carries missing `(targetId, hostLabel, cli)` list for tooltip / banner

## Out of scope

- Pre-install on Machines **save** without user clicking Install  
- Preferring npmmirror / download policy changes  
- Connect-time auto-install (explicitly removed; locate-only on connect)
