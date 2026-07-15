# `list_teammates` machine identity + member cwd

**Status:** Approved  

**Date:** 2026-07-15

## Problem

Mixed teams place roster members on different machines (`local` / SSH / WSL). Agents calling TeamBus MCP `list_teammates` see identity, CLI, and bus state, but **not** which host a teammate runs on, or that member’s work path on that host.

Today’s `cwd` on the roster profile is filled with `session.firstFolderPath` at bus install — wrong when a member is pinned to another target’s folder.

Cross-machine artifact transfer already resolves `memberId → RuntimeTarget.id` via `launchWorkTarget`, but that mapping is not exposed on the roster snapshot.

## Goal

At bus install time, snapshot each member’s machine placement into `TeammateRosterProfile`, and expose it (plus the correct per-member cwd) from `list_teammates`.

Agents should be able to answer: “Is `developer` on `root@localhost:22` under `/home/root/proj`?”

## Non-goals

- Live re-resolution when Machines placement changes mid-session (session restart / re-install bus remains the refresh path).
- Exposing SSH credentials, private keys, or auth type.
- Changing artifact transfer APIs (`targetForMember` stays as today).
- UI changes to Machines / landing placement.
- Enriching local machine with OS hostname / login user (local stays the literal `local`).

## Decisions

1. **Install-time snapshot** into `TeammateRosterProfile` (same lifetime as `cwd` / `cli`).
2. **Human machine string** field `machine`:
   - `local` → `"local"` (same string as `machineId`)
   - `ssh` → `SshProfile.hostIdentifier` (`username@host:port`); if profile missing → fall back to `target.id`
   - `wsl` → `"wsl:<distro>"` (same string as `machineId`; intentional)
3. **Also store** `machineId` (`RuntimeTarget.id`) and `machineKind` (`RuntimeKind.name`: `local` | `ssh` | `wsl`) so agents and artifact tooling share the same vocabulary.
4. **Fix member `cwd`** at install via `lifecycle.memberWorkDirs(WorkspaceLaunchContext, memberId).workingDirectory` (same catalog merge as connect/launch). Do **not** use `session.firstFolderPath` for member profiles. Team-header `TeamSessionContext.workingDirectory` stays `session.firstFolderPath` (unchanged).
5. **No per-member `additional_paths` in this change.** Team-header `additional_paths` from `TeamSessionContext` remains as today; member `addDirs` are not listed on roster rows.

## Output shape (`formatTeammate`)

**Superseded:** prose `machine:` / `machine.kind:` / `machine.id:` lines are replaced by JSON keys on the roster member object. See [`2026-07-15-mixed-team-machine-ui-and-teambus-json-design.md`](./2026-07-15-mixed-team-machine-ui-and-teambus-json-design.md) Track B.

**Empty-machine rule (unchanged):** emit `machine` / `machine_kind` / `machine_id` **iff** `machineId.isNotEmpty`; otherwise omit all three. Production `installBusForTab` always fills all three (local → `"local"` / `"local"` / `"local"`).

Update `ListTeammatesTool.description` to mention machine + cwd (and JSON output).

## Architecture

```
installBusForTab(session, team)
  for each runtime member:
    target = launchWorkTarget(ctx, memberId)
    machine* = resolve from target (+ sshProfileById when kind==ssh)
    cwd / addDirs = memberWorkDirs(ctx, memberId)
    TeammateRosterProfile.fromMember(..., machine*, cwd)
      → bus.declareMember

list_teammates
  → encodeRoster → formatTeammate reads profile.machine*
```

### Wiring

- `TabTeamBusCoordinator.installBusForTab` needs ChatCubit-injected wrappers (same shape as `MemberLifecycleConnectGate` / artifact factory), **not** raw lifecycle calls with bare `AppSession`:
  - `RuntimeTarget Function(AppSession session, {String? memberId}) launchWorkTarget` → wraps `lifecycle.launchWorkTarget(launchContextFor(session), …)`
  - `({String workingDirectory, List<String> addDirs}) Function(AppSession session, String memberId) memberWorkDirs` → wraps `lifecycle.memberWorkDirs(launchContextFor(session), …)`
  - `SshProfile? Function(String profileId)? sshProfileById` (already on ChatCubit shell factory)
- Prefer extracting a pure helper `rosterMachineFromTarget(RuntimeTarget target, {SshProfile? profile})` → `{machine, machineKind, machineId}` for unit tests without standing up the coordinator.
- Prefer **not** importing UI cubits into TeamBus format code; resolution stays at install.

### Profile fields

Add to `TeammateRosterProfile`:

| Field | Type | Default |
|-------|------|---------|
| `machine` | `String` | `''` |
| `machineKind` | `String` | `''` |
| `machineId` | `String` | `''` |

`fromMember` gains optional named params for the three machine fields (and keeps `cwd`). Callers that omit them behave as today for unit tests that only care about id/cli.

`TeammateRosterProfile.minimal` leaves machine fields empty unless tests pass them.

## Error / fallback behavior

| Case | Behavior |
|------|----------|
| SSH target, profile found | `machine = hostIdentifier` |
| SSH target, profile missing | `machine = target.id` (still emit kind/id) |
| No member pin / fallback folder | Same as `launchWorkTarget` today (first folder / local) |
| Member cwd | Trust `memberWorkDirs` / `workDirsForMember` (already falls back to `firstFolderPath` when unpinned or target paths empty); no second install-time policy |

## Testing

- Unit: `rosterMachineFromTarget` for local / ssh (+ profile) / ssh (no profile) / wsl.
- Unit: `TeammateRosterProfile.fromMember` accepts and stores machine fields.
- MCP JSON emit / omit of `machine` / `machine_kind` / `machine_id` is covered by Track B tests (not this design’s prose era).
- Existing roster / MCP handler tests keep passing until Track B updates them for JSON.

## Out of scope follow-ups

- Mid-session placement refresh without bus reinstall.
- Showing `same_machine: true/false` relative to the caller (derivable by agents from `machine.id`).
