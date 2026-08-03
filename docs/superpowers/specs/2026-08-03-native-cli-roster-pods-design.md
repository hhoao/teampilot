# Native CLI roster = session pods (design)

**Date:** 2026-08-03  
**Status:** Approved for planning  
**Scope:** Align Claude native-team CLI roster identity (`teams/.../config.json`, inboxes, `--agent-id`) with session pods so SendMessage targets the same ids as running shells. Identity alignment only.

## Problem

TeamPilot has two member layers:

| Layer | Source | Example |
|-------|--------|---------|
| **Type** (template) | `TeamProfile.roster` / `team.members` | `developer` with `replicas: 2` |
| **Pod** (runtime instance) | `AppSession.members` → `sessionRosterMembers` | `developer-0`, `developer-1` |

UI, presence, and PTY launch already use **pods**. Native Claude team staging still passes **`team.members` (types)** into `ClaudeTeamRosterService`, which writes:

- `teams/<cliTeamName>/config.json` with `name: developer`, `agentId: developer@…`
- `inboxes/developer.json`

While shells launch as:

- `--agent-name developer-0 --agent-id developer-0@…`

Lead `SendMessage(to: "developer")` succeeds into `inboxes/developer.json`, but no running process polls that inbox. Replica shells idle forever; `replicas: 0` roles (e.g. reviewer) receive messages with no process at all.

Root cause: **type roster was treated as CLI roster**.

## Goals

1. Single source of truth for “who is in this session’s CLI team”: **session pods**.
2. Claude `config.json` member `name` / `agentId`, inbox filenames, and CLI `--agent-name` / `--agent-id` all use the **same pod id**.
3. Native mode keeps supporting `replicas > 1`: each pod is a first-class Claude teammate (no type-name aliasing).
4. `replicas: 0` (or otherwise absent from `AppSession.members`) does not appear in the CLI roster.
5. Launch staging paths stop passing `team.members` into Claude roster writers.

## Non-goals

- Type-name SendMessage aliases (`to: "developer"` fan-out or unicast).
- Idle / inbox wake-up (doorbell, nudge) if Claude already polls a matching inbox.
- Changing `teammateMode` (in-process vs external PTY) semantics.
- Mixed-mode TeamBus protocol changes (already pod-based via `sessionRosterMembers`).
- Redesigning placement UI or type-level roster editing.

## Decisions (locked)

1. **Replicas in native:** supported; each pod is an independent Claude member.
2. **Addressing:** pure pod ids only; `SendMessage(to: "developer")` failing when only `developer-0`/`developer-1` exist is expected.
3. **Scope:** identity alignment only.

## Architecture

### Type vs pod (unchanged product model)

- **Type** remains the template: expert, replicas count, placement targets, presets.
- **Pod** remains the runtime unit: terminal seat, presence, session binding, task id.
- Editing replicas / experts continues to mutate **type** data (`team.members` / roster overrides).

### CLI roster resolver

Add `cliTeamRosterMembers(AppSession session, TeamProfile team)` next to `sessionRosterMembers` in `client/lib/models/app_session.dart` (or an adjacent small library file if preferred for cycle reasons).

**Behavior for this change:** delegate to `sessionRosterMembers(session, team)`.

**Why a separate name:** call sites express intent (“this list feeds CLI/Claude roster”). UI/presence may keep calling `sessionRosterMembers`. If CLI and UI lists diverge later, only the CLI wrapper changes.

**Invariants:**

- Output member `id` is the pod id (`developer-0`, not `developer` when `replicas > 1`).
- Singleton types (`replicas <= 1` and a single binding) keep bare type id (`developer`).
- Lead stays `team-lead` (bare `--agent-id team-lead` rule unchanged).
- Members not in `session.members` are omitted (covers `replicas: 0` and placement-omitted pods).

### Hard rule

Any path that writes Claude `teams/<cliTeamName>/config.json`, ensures `inboxes/*.json`, or builds native `--agent-name` / `--agent-id` **must** consume one of:

- `cliTeamRosterMembers(session, team)` when an `AppSession` exists, or
- `runtimeRosterMembers(team)` when staging without a session (preview / environment)

Passing `team.members` into those writers is forbidden.

`--agent-name` / `--agent-id` already derive from the **launched** member config id (`CliLaunchContext.memberCliId`). Fixing the staged roster list is what closes the gap with inbox / config.json.

### Claude roster write behavior

`mergeConfig` / `ensureInboxes` stay keyed by `member.id`. The **input list** must be pods. One related seeding rule is required so `agentType` does not collapse to the pod id:

**`agentType` rule:** For a pod derived from type `developer`, Claude config `agentType` must be the **type/role id** (`developer`), not `developer-0`.

Today `TeamMemberNaming.resolveAgentType` falls back to `member.id` when `agentType`/`agent` are empty. After switching inputs to pods, that fallback would wrongly write `agentType: developer-0`.

**Required small change (not “input-only”):** when expanding Deployment→Pod (`MemberInstance.toMemberConfig`, used by `sessionRosterMembers` / `runtimeRosterMembers`), seed:

- `agentType`: existing non-empty `type.agentType`, else non-empty `type.agent`, else **`type.id`**

So `ClaudeTeamRosterService.buildMemberEntry` can keep calling `resolveAgentType` unchanged and still emit role-level `agentType`.

| Field | Value |
|-------|--------|
| `name` | pod id |
| `agentId` | `TeamMemberNaming.cliAgentId(memberId: podId, cliTeamName: …)` |
| `agentType` | type/role id (seeded as above), e.g. `developer` for `developer-0` |
| inbox file | `inboxes/<safe(podId)>.json` |

Each staging pass **rewrites** `config.json` from the current pod list (existing merge preserves `joinedAt` / `isActive` when agentId matches). Type-only rows (e.g. stale `developer`) that are not in the current pod list are **not** re-emitted, so lead does not see ghost teammates.

Stale `inboxes/<type>.json` files from older sessions may remain on disk; **no delete requirement**. New writes create/ensure pod inbox files only.

Member settings files already use launched pod ids (`settings/developer-0.json`); no change required there.

### Call sites to change

**Session launch staging** (have `AppSession`):

1. `client/lib/services/launch/session_connect_orchestrator.dart` → `stageTeamLaunch`
2. `client/lib/services/session/session_lifecycle_service.dart` → `prepareTeamLaunch` used by live seat connect

Use: `members: cliTeamRosterMembers(session, team)`.

**No-session / preview staging** (e.g. `prepareTeamLaunchEnvironment` → `TeamLaunchService`):

There is no placement-filtered `AppSession`. Use: `members: runtimeRosterMembers(team)` (expand from type `replicas`, same pod id rules).

Never pass `team.members` into Claude roster writers on either path.

### Call sites that stay on types

Placement, landing team settings, and other **template** editors keep using `team.members` / roster overrides. They do not write Claude session `teams/.../config.json` for a live session’s messaging identity.

### Optional guard

Debug-only assert or log when native staging receives a member id that looks like an unreplicated type while the session bindings show numbered pods for that type (detect accidental `team.members` regression).

## Data flow (after)

```
AppSession.members (bindings)
  → cliTeamRosterMembers / sessionRosterMembers (pods)
  → stageTeamLaunch / prepareTeamLaunch (members: pods)
  → ClaudeTeamRosterService.mergeConfig + ensureInboxes
  → teams/<cliTeam>/config.json + inboxes/<pod>.json

same pod id
  → TerminalSession connect
  → --agent-name <pod> --agent-id <pod>@<cliTeamName> (lead: team-lead)
```

Lead SendMessage targets pod names from config; messages land in matching inboxes; matching agent processes consume them.

## Testing

1. **Unit — resolver:** `developer.replicas=2`, `reviewer.replicas=0` → pods `team-lead`, `developer-0`, `developer-1`; no `reviewer`; pod configs seed `agentType`/`capabilities` so role id is `developer`.
2. **Unit — roster merge:** merge with those pods → config names/agentIds are pods; `agentType` is `developer`; no bare `developer` / `reviewer` rows; inboxes ensured for each pod.
3. **Config / staging:** prepare or stage a native team launch with a session that has numbered developer bindings; assert disk `config.json` and `inboxes/developer-0.json` exist and a type-level `developer.json` is not created for that new write path.
4. **Unit — singleton:** `replicas=1` keeps bare `developer` id in resolver + merge.

## Acceptance

For a new native session with `developer.replicas=2` and `reviewer.replicas=0`:

1. Claude roster members are `team-lead`, `developer-0`, `developer-1` only.
2. Config rows for pods use `agentType: developer` (not `developer-0`).
3. `SendMessage(to: "developer-0")` writes `inboxes/developer-0.json`.
4. The `developer-0` PTY is launched with `--agent-id developer-0@<cliTeamName>` (same identity as inbox / config).

Also: singleton (`developer.replicas=1`) keeps bare `name`/`agent-name`/`inbox` id `developer` (no `-0` suffix).

## Implementation notes

- Prefer thin wrapper + call-site swap; plus the `agentType` seed on `MemberInstance.toMemberConfig`.
- Avoid duplicating replica expansion logic.
- Update AGENTS.md guidance: **CLI native roster writers** must use `cliTeamRosterMembers(session, team)` or, without a session, `runtimeRosterMembers(team)` — never raw `team.members`.
- Existing sessions with stale type-level `config.json` are healed on next staging rewrite when pods are passed in.
