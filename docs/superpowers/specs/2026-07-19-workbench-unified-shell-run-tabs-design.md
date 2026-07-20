# Workbench unified shell + Run tabs (Orca-aligned)

**Date:** 2026-07-19  
**Status:** Draft for planning  
**Related:** Orca unified `TabBar` / `TerminalTab` (agent + shell peers); TeamPilot `WorkbenchCubit`, `WorkspaceBottomDock`, `WorkspaceTerminalRegistry`, `RunCubit`

## Problem

The workspace IDE keeps agent sessions (and file/diff) in the **center** workbench tab strip, while workspace shell PTYs and Run output live in a **bottom dock**. That dock:

- Steals vertical space from the primary agent workbench whenever it is open
- Duplicates tab-chip UX beside an already-unified center strip (`session` / `file` / `diff`)
- Is weaker than Orca’s model, where shell and agent terminals are **peer tabs** in one strip (distinguished by icons, not by a second container)

Users prefer eliminating the bottom bar and hosting shell + Run in the center workbench, following Orca.

## Goals

- Remove `WorkspaceBottomDock` and the bottom split of `WorkspaceIdeShell`
- Treat **shell** and **run** as first-class center workbench tabs alongside `session` / `file` / `diff`
- Align with Orca: one ordered tab strip, mixed kinds, icon discrimination, no type-based row grouping
- Preserve PTY / Run process lifecycle across tab switches (keep-alive body)
- Retarget Run “reveal tool window” intents to center `ensureTab` + `select`

## Non-goals (v1)

- Orca-style **global floating workspace** (optional later companion)
- Putting shells inside a session’s member PTY list
- Changing “one session tab → many member PTYs” for team mode
- Split-pane **TabGroup** layouts (Orca multi-strip); v1 is one strip per workspace center
- Empty “New Run” from the `+` menu (Run still starts from run configurations / quick run)

## Product decisions (locked)

| Choice | Decision |
|--------|----------|
| Approach | Full unification (shell + Run together); no half-migration with dual selection owners |
| Tab species | Extend `WorkbenchTabKind` with `shell` and `run` |
| Strip | Single `WorkbenchCubit.tabOrder`; mixed order; no agent/shell sections |
| Discrimination | Icons + titles only (session = agent chrome; shell = terminal; run = play/status) |
| Close shell | Close tab **disposes** the `WorkspaceTerminalEntry` (hard link; no orphan entries) |
| Close run | Existing dismiss confirm path, then remove workbench tab |
| Preview slot | Shell / Run are **always pinned**; do not enter or displace the shared session/file/diff preview slot |
| `+` menu | New chat (compose) + New terminal (existing local/SSH/WSL catalog); not empty Run |
| Former bottom toggle / `togglePanel` | No dock toggle. Shortcut: **if no shell tab → create default local shell; else focus most recent shell** (definition below) |
| “Most recent shell” | Prefer the shell tab last selected via `WorkbenchCubit` for this workspace (track `lastFocusedShellTabId` or equivalent). If none recorded, use the **rightmost** `shell` entry in `tabOrder`. Do **not** invent a third ordering from registry `activeId` alone. |
| Default local shell | Reuse existing create path (`defaultSessionSpecFor` + `HostInteractiveShell.defaultExecutable()` via `WorkspaceTerminalSessionOps.openEntry` / equivalent) — do not invent a parallel default |
| Compose | Unchanged: `activeTabId == null` (or explicit new-chat) shows landing; closing all shell/run tabs does **not** force compose |
| Floating workspace | Out of v1 |
| Persistence of shell tabs across app restart | Not required in v1 (same as today’s ephemeral dock shells unless already persisted elsewhere) |
| Bulk close | `closeOthers` / `closeRight` (and any close-all helpers) must run **per-kind** teardown for every removed tab: dispose shell entries, dismiss runs, existing session/file/diff close — never strip-only remove for shell/run |

## Tab model

| Kind | Identity | Body | Close |
|------|----------|------|-------|
| `session` | `sessionId` | `ChatWorkbench` | Existing session close |
| `file` / `diff` | path / diff key | Editor / diff surfaces | Existing |
| `shell` | `entryId` → `WorkspaceTerminalEntry` | Shell terminal surface (no dock chrome / no inner chip row) | Dispose entry |
| `run` | Run `sessionId` → `RunSession` | `RunPanel(showChrome: false)` | Dismiss run |

Factories:

```dart
WorkbenchTabId.shell(String entryId);
WorkbenchTabId.run(String runSessionId);
```

Delete dock-local selection (`WorkspaceDockTab`, dock `_active`). Selection is only `WorkbenchCubit.activeTabId`.

## Architecture

```
WorkspaceIdeShell
└── left | center | right          // no bottom split
         └── WorkspaceShell strip  // session|file|diff|shell|run
              + WorkbenchBody
                   ├── session → ChatWorkbench
                   ├── file/diff → existing surfaces
                   ├── shell → single-entry terminal surface (keep-alive)
                   └── run → RunPanel (keep-alive)
```

### Ownership

| Unit | Owns | Does not own |
|------|------|--------------|
| `WorkbenchCubit` | `tabOrder`, `activeTabId`, preview set; ensure/select/remove for all kinds | PTY connect, Run process |
| `WorkspaceTerminalRegistry` | Shell entry create/dispose/connect | Whether a tab chip exists |
| `RunCubit` (+ run session manager) | RunSession lifecycle, logs | Bottom dock visibility |
| `WorkbenchBody` | Kind → surface | Second chip list |
| `WorkbenchShellActions` | Select/close routing into domain + cubit; update `lastFocusedShellTabId` on shell select | — |
| `WorkbenchShellRunSync` (new, name flexible) | Passive ensure+select for new RunPanel sessions; passive `removeTab` when domain drops shell/run; peer to `WorkbenchSessionSync` | Owning PTY/Run processes |

Same pattern as today’s session/file: **strip identity in WorkbenchCubit; domain state in existing services.**

### Lifecycle

**New shell**

1. Registry `addEntry` → `entryId`
2. `workbench.ensureTab(workspaceId, WorkbenchTabId.shell(entryId), preview: false)`
3. Lazy connect (keep current “no PTY until needed” behavior)

**Start Run (explicit + passive)**

1. `RunCubit` creates session (unchanged)
2. **Passive parity with today’s dock:** whenever a Run session that uses the Run panel appears in the workspace session list (dock’s `_onSessionsChanged` / `_sessionUsesRunPanel` equivalent), `ensureTab(..., WorkbenchTabId.run(id))` **and `select` that new run tab** (dock sets `_active` to the added run — center must match; this may steal focus from the current session/file tab, same as today’s reveal)
3. `RunUiIntent` with activate/focus: keep `surface` / `activateToolWindow` / `focusToolWindow` / `terminalEntryId` semantics; map to workbench ensure+select (replace `dockTabForActivateIntent`)
4. **Which tab to focus on intent:** `RunToolSurface.terminal` → `WorkbenchTabId.shell(terminalEntryId)` when `terminalEntryId` is set (required for terminal surface). `RunToolSurface.run` → select the **latest** RunPanel session for the workspace. v1 does **not** add `runSessionId` on `RunUiIntent` (model today has only `terminalEntryId`); latest-run bias matches the dock

**Domain → strip reconciliation (passive ensure + remove)**

`tabOrder` is no longer derived from registry/RunCubit, so domain changes must push strip updates via `WorkbenchShellRunSync` (name flexible; peer to `WorkbenchSessionSync`):

- **Passive shell ensure (no forced select):** whenever a registry entry appears for the workspace (dock mirrored every entry via `ListenableBuilder`, including Shell Script `openForRun` with `activateToolWindow: false`), `ensureTab(..., WorkbenchTabId.shell(id), preview: false)` **without** selecting unless an intent/shortcut asks to focus
- **Passive run ensure + select:** as above for new RunPanel sessions
- **Passive remove:** shell entry dispose / `disposeWorkspace` / run dismiss / `WorkspaceRunRegistry.removeScope` → `removeTab` if present
- **Title-bar workspace close:** do not rely only on a widget-scoped listener (widget may unmount before registry dispose). Also run an **explicit** strip cleanup in the close path (`WorkbenchCubit` clear workspace shell/run tabs or equivalent) alongside domain teardown

**Switch tabs**

- Non-active shell/run bodies stay **mounted but hidden** (IndexedStack / Offstage or equivalent) so PTY and Run state survive — same intent as today’s bottom-pane pixel-hide
- **PTY resize hold:** today’s `WorkspaceTerminalHoldHandle` is wired from bottom-dock ↔ `WorkspaceIdeShell` split drag. After dock removal, center shell surfaces must still receive hold during **sidebar / right-tools** (and any remaining) split drags so resize does not regress PTY behavior — re-home the hold wiring onto the IDE shell / center body, not drop it
- Store `lastFocusedShellTabId` on `WorkbenchWorkspaceState` (or equivalent per-workspace bucket). Update it on **every** successful select of a shell tab (in `WorkbenchShellActions.select` or equivalent), not only when the togglePanel shortcut runs

**Close**

- Shell: dispose registry entry + `removeTab`
- Run: existing dismiss + `removeTab`
- Bulk close (`closeOthers` / `closeRight`): for each removed id, invoke the same per-kind teardown (shell dispose, run dismiss, …) before or as part of strip updates — strip-only removal is a bug
- `syncSessions` reconciles **session** tabs only; must never drop shell/run entries
- Title-bar workspace close/reopen: explicit cleanup + domain teardown must leave no stale shell/run ids in `tabOrder`

**Scope**

- Workbench strip keyed by **`workspaceId`** (today’s `WorkbenchCubit`)
- Terminal registry / RunCubit scopes use **`tabScopeId`** where that already differs — `WorkbenchShellRunSync` must map workspace ↔ scope the same way the dock/`WorkspaceToolsScope` does today so shells do not cross-wire across title-bar workspaces
- Background title-bar workspaces must not share selection across instances

### UI

- Remove `WorkspaceBottomDock`, `WorkspaceShellBottomDockVisibilityToggle`, and `workspaceTerminalVisible`-driven bottom pane policy (prefer field deprecated: ignore on read; stop writing from UI)
- Extend **tab projection** (`projectWorkbenchTabs` / equivalent): shell titles via `WorkspaceTerminalTitleResolver` (or entry `titleLabel`); run titles from `RunSession`; shell/run **not** preview-pinnable (`pinnable: false` / never enter preview set)
- Extend `WorkspaceShellTabChip` (or equivalent) for shell/run icons; do not keep a second dock chip component
- Center `+` becomes a small menu: New chat → compose; New terminal → existing `WorkspaceTerminalNewSessionMenu`
- Shell body has **no** nested tab strip; switching shells is only via the center strip
- Run body may keep Run-specific controls (stop / clear / re-run); tab title stays on the strip

### Removal / migration surface

| Remove or rewire | Notes |
|------------------|-------|
| `WorkspaceBottomDock` | Delete after center path works |
| `WorkspaceDockTab` | Replaced by `WorkbenchTabId` |
| `dockTabForActivateIntent` | Replace with workbench ensure/select helper |
| `LayoutCubit` bottom visibility APIs / title-bar toggle | Delete UI; deprecate preference |
| `WorkspacePanePolicy.dockBottom` | Always false / remove |
| l10n for bottom dock toggle | Clean up unused |

## Risks

| Risk | Mitigation |
|------|------------|
| PTY disconnect on tab switch | Keep-alive body; manual + widget tests for session↔shell↔file |
| `syncSessions` wipes shell/run | Unit test: sync preserves non-session kinds |
| Preview eviction | Shell/run never preview |
| Dual selection during migration | Ship without half-state: no dock `_active` once center owns tabs |
| Crowded strip | Accept Orca-style mix; scroll/pin polish later |

## Test plan

**Unit / cubit**

- `WorkbenchTabId.shell` / `.run` equality
- `ensureTab` shell/run pinned; does not replace session preview
- Closing shell/run does not force compose
- `syncSessions` keeps shell/run in `tabOrder`
- Intent mapper: activate terminal/run → correct `WorkbenchTabId` (explicit id vs latest run)
- Passive: new RunPanel session → `ensureTab(run)` **and** `select` (may steal focus)
- Passive remove: domain dismiss/dispose/scope teardown → strip `removeTab`; no orphan shell/run ids after title-bar workspace close
- `closeOthers` / `closeRight` dispose shell entries and dismiss runs for removed tabs
- `togglePanel` equivalent: no shell → default local open path; else select `lastFocusedShellTabId` or rightmost shell
- `lastFocusedShellTabId` updates on every shell select

**Widget / integration**

- New shell appears on strip and renders terminal surface
- Run start activates run tab and `RunPanel`
- Close shell disposes entry; close run follows dismiss
- IDE shell has no bottom child; no bottom visibility toggle
- Sidebar/right-tools drag still holds shell PTY resize (hold handle re-homed)

**Manual smoke**

- Local / SSH / WSL shells; switch away and back still connected
- Run success/failure chrome; dismiss confirm
- Multi title-bar workspace: shells do not cross-wire

## Implementation order

1. Extend `WorkbenchTabKind` + factories; `WorkbenchBody` branches (optional short dual-mount only if needed for green tests — prefer not to leave dock selection live)
2. Wire create/close through `WorkbenchShellActions` + registry/RunCubit; add `WorkbenchShellRunSync` (passive ensure/select + passive remove)
3. Tab chip icons/titles; `+` menu; `projectWorkbenchTabs` projection
4. Retarget `RunUiIntent` (latest-run focus; terminalEntryId for shell)
5. Keep-alive mounting + PTY hold re-home; PTY regression checks
6. Remove dock, toggles, pane policy bottom, dead types
7. Prefer deprecate + analyze/test clean

## Acceptance

- No workspace bottom tool dock; agent workbench uses full center height
- Shell and Run exist only as center workbench tabs
- One selection owner (`WorkbenchCubit`); Orca-like mixed strip with icon discrimination
- Goals above met; non-goals not implemented in v1
