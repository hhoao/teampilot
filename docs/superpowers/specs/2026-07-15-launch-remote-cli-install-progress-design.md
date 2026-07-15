# Launch-time remote CLI install progress (UI)

**Status:** Approved (approach A)  
**Date:** 2026-07-15

## Problem

When a mixed-team member is pinned to SSH and the remote host lacks Node/CLI, `WorkspaceProvisioner.ensureReady` runs auto-install on the connect hot path. Progress is log-only. Local members finish first; the SSH member stays `pending` / offline with no pane feedback.

## Decision

On launch (connect), when off-home workspace provision is installing CLI tooling for a member, show `CliInstallProgressPanel` on that member’s terminal pane with live phase updates. Do not pre-install on Machines save (deferred).

## Design

1. **Progress plumbing** — `WorkspaceProvisioner.provision` / `_ensureCli` and `WorkspaceProvisionCoordinator.ensureReady` accept an optional progress callback carrying `CliInstallPhase` (+ optional detail / host label). Remote install already reports phases; surface them instead of string-only logs.
2. **Tab state** — Per member on `ChatTab`: in-flight provision UI state (`phase`, `detail`, `hostLabel`, `error`). Cleared when provision finishes or fails. Drive cubit notify so workbench rebuilds.
3. **Connect path** — `SessionConnectOrchestrator` / shell connector, when calling `ensureReady` for an SSH member, wires progress → tab state for that `memberId`.
4. **UI** — In `ChatWorkbench` terminal `Stack`, if the selected member has active provision progress (or failed with message), show the progress/error panel. Independent of session-level `sessionConnectingId` (team-lead may already be connected while builder-1 installs).
5. **Failure** — On install failure, set error on that member’s progress state, remove from `membersPendingConnect` (existing finally), allow retry via existing connect paths.

## Out of scope

- Background install on Machines placement save  
- Preferring npmmirror / download timeout policy changes (separate)  
- Changing auto-install opt-in defaults  

## Superseded

Connect-time auto-install + launch-time install progress as the primary UX was superseded by
[`2026-07-15-landing-remote-cli-gate-design.md`](./2026-07-15-landing-remote-cli-gate-design.md)
(Machines Install button + landing gate; connect is locate-only).
