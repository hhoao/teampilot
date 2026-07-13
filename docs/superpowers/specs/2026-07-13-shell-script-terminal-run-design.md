# Shell Script Terminal Run (IDEA-aligned)

**Date:** 2026-07-13  
**Status:** Approved (spec review)  
**Depends on:** [2026-07-11-workspace-run-platform-design.md](./2026-07-11-workspace-run-platform-design.md)  
**Owner decision:** Replace the built-in Run type `process` with IDEA-style **Shell Script**. Default execution injects into the **workspace Terminal** (interactive). Keep a non-terminal path when `executeInTerminal` is off. Extension-contributed `launch-type`s remain the path for all other runtimes. Prefer IDEA field names and UX over preserving `process` as a user-facing type.

## Problem

The workspace Run platform ships a built-in `process` type that spawns via `Process.start` / SSH exec and shows output in the bottom **Run** log panel. That matches neither JetBrains Shell Script configs nor user expectation for interactive scripts (prompts, TUI, Ctrl+C in a real TTY).

Workspace Terminal already provides interactive PTY tabs, but has no first-class “open/reuse tab + inject command” API. Users who want IDEA-like Shell Script must either misuse `process` (non-interactive) or paste into Terminal manually.

## Goals

- Built-in type **`shellScript`** aligned with IDEA Shell Script configuration fields.
- Default: **Execute in the terminal** — open/reuse a workspace Terminal tab and inject the assembled command.
- Configurable: `allowMultipleInstances`, `executeInTerminal`, `activateToolWindow`, `focusToolWindow`.
- Add-config UX: type picker (built-in Shell Script + enabled extension types).
- Migrate existing `type: "process"` entries on read (compat alias) with **deterministic** mapping so common configs still run.
- Extract a small **`WorkspaceTerminalRunService`** so Run does not reach into panel-private methods.
- Unify top-bar Stop via a **lightweight `RunSession`** for terminal-backed runs.

## Non-goals

- Before launch / Tasks system (still out of scope per Run platform non-goals).
- “Show this page before run.”
- Full Debug / DAP.
- Replacing extension Launch Adapter types or the Run panel for adapter/`executeInTerminal: false` sessions.
- Shipping first-party language adapters in core.
- Perfect Windows interpreter discovery in v1 (sensible defaults + explicit path field are enough).
- Prompt heuristics beyond “PTY transport ready” for injection timing (no ANSI prompt scraping in v1).
- Tracking real script exit codes in terminal mode (v1: session ends on Stop or tab dispose only).

## Decision

**Approach A: Terminal inject after connect**, with IDEA-shaped config toggles.

```text
Run ▶ (type shellScript)
  → expand + validate Shell Script fields
  → build command line (interpreter + options + script + script options)
  → if executeInTerminal:
       register lightweight RunSession (starting)
       WorkspaceTerminalRunService.openOrReuse(selectionKey)
         → ensure Terminal tab (cwd, shell for owning folder targetId)
         → wait transport ready (same gate as manual Terminal connect)
         → session.input.writeToPty(command + CR)
         → RunSession → running
         → optional activate/focus bottom Terminal
     else:
       existing ProcessRunExecutor + Run panel (assembled as argv / shell command)
```

Rejected for this change:

| Alternative | Why not |
|-------------|---------|
| B: PTY spawn = script process itself | Cleaner stop semantics, but not IDEA “shell then run”; user chose A |
| Keep `process` as the public built-in name | Diverges from IDEA; confuses type picker |
| Always inject into active tab only | No multi-instance / named reuse; IDEA exposes Allow multiple instances |
| Parallel “terminal handle” map outside `RunSessionManager` | Splits Stop / already-running UX; rejected in favor of lightweight `RunSession` |

## Config model

### Type identity

| Wire `type` | Role |
|-------------|------|
| `shellScript` | Canonical built-in type |
| `process` | Read-only alias → normalize to `shellScript` on load; writers emit `shellScript` |

### Variable expansion

All string fields (`scriptPath`, `scriptText`, `scriptOptions`, `cwd`, `interpreterPath`, `interpreterOptions`, env values) expand per the parent Run platform rules (`${workspaceFolder}`, `${env:NAME}`, …) **before** validate/build.

### Example `.teampilot/launch.json` entry

```json
{
  "id": "run-smoke",
  "name": "Smoke script",
  "type": "shellScript",
  "request": "launch",
  "execute": "scriptFile",
  "scriptPath": "${workspaceFolder}/scripts/smoke.sh",
  "scriptOptions": "",
  "cwd": "${workspaceFolder}",
  "env": {},
  "interpreterPath": "/bin/bash",
  "interpreterOptions": "",
  "executeInTerminal": true,
  "allowMultipleInstances": false,
  "activateToolWindow": true,
  "focusToolWindow": false
}
```

Script-text variant uses `"execute": "scriptText"` and `"scriptText": "echo hello"` (no `scriptPath` required).

### Field map (IDEA → TeamPilot)

| IDEA | Field | Default | Notes |
|------|-------|---------|-------|
| Name | `name` | — | Existing |
| Allow multiple instances | `allowMultipleInstances` | `false` | Tab reuse vs always new |
| Store as project file | — | always | Already folder `launch.json` |
| Execute: Script file / Script text | `execute` | `scriptFile` | enum `scriptFile` \| `scriptText` |
| Script path | `scriptPath` | — | Required when `scriptFile` |
| Script text | `scriptText` | — | Required when `scriptText` |
| Script options | `scriptOptions` | `""` | Args string after script |
| Working directory | `cwd` | `${workspaceFolder}` | |
| Environment variables | `env` | `{}` | Applied when possible (see below) |
| Interpreter path | `interpreterPath` | platform default | e.g. `/bin/bash` |
| Interpreter options | `interpreterOptions` | `""` | |
| Execute in the terminal | `executeInTerminal` | `true` | New configs only; see migration |
| Activate tool window | `activateToolWindow` | `true` | Reveal bottom dock + Terminal (or Run) |
| Focus tool window | `focusToolWindow` | `false` | Request focus on that surface |
| Show this page | — | — | Non-goal |
| Before launch | — | — | Non-goal |

### `process` migration (deterministic)

On load, if `type == "process"`, normalize in memory (and on next user save write `shellScript`):

**Shared defaults for migrated configs:**

| Field | Value | Rationale |
|-------|-------|-----------|
| `executeInTerminal` | `false` | Preserve prior non-TTY Run-panel semantics |
| `allowMultipleInstances` | `false` | Match prior single-session default |
| `activateToolWindow` | `true` | |
| `focusToolWindow` | `false` | |
| `cwd` / `env` | unchanged | |

**Branching rules** (apply in order; first match wins):

1. **`shell: true`**  
   - `execute` = `scriptText`  
   - `scriptText` = join `command` + `args` with spaces (preserve prior shell line)  
   - `interpreterPath` = platform default shell (`/bin/bash` or `/bin/sh`)  
   - `interpreterOptions` = `""`  
   - `scriptOptions` = `""`

2. **Else (`shell` absent/false)** — treat as executable + args (e.g. `flutter` + `["run"]`):  
   - `execute` = `scriptText`  
   - `scriptText` = shell-quoted join of `command` and each `args` element (same effective argv as before)  
   - `interpreterPath` = platform default shell  
   - `interpreterOptions` = `""`  
   - `scriptOptions` = `""`  
   - Non-terminal and terminal execution both run this as **shell/`scriptText`** (e.g. default shell `-c` with the joined line). Do **not** keep a parallel argv-direct path after migration.

3. Drop obsolete keys (`command`, `args`, `shell`) from the normalized model; do not leave dual representations.

Writers never emit `type: "process"`.

## Runtime behavior

### Command assembly

Conceptual line injected / executed in terminal mode:

```text
cd <cwd> && <env exports…> <interpreterPath> <interpreterOptions…> <scriptPath|-c scriptText> <scriptOptions…>
```

Principles (tactics such as exact `-c` quoting may be refined in the plan):

- One injectable line ending with `\r` for terminal mode.
- Quote paths/args safely for the target shell (local / WSL / SSH).
- Prefer spawning the login shell already in expanded `cwd` when creating the tab; still include `cd` on the inject line if the bound tab’s cwd may have drifted.
- Env: best-effort `export`/`VAR=value` prefixes on the inject line; do not rewrite login-shell spawn in v1.

### Terminal-backed session lifecycle

Terminal-backed Shell Script runs **always** register a lightweight session in `RunSessionManager` so top-bar Stop / already-running UX stays unified.

| State | When |
|-------|------|
| `starting` | Session registered until inject succeeds or fails |
| `running` | After successful inject |
| `exited` | User Stop (Ctrl+C inject), tab disposed while bound, or explicit cancel while running |
| `failed` | Connect failure, transport-ready timeout, or inject failure — use existing `RunSessionStatus.failed` + `errorMessage` (same Run panel / toolbar error surfacing as process launches) |

v1 does **not** observe script exit codes from the PTY; the shell tab may keep running after the script finishes while the lightweight `RunSession` remains `running` until Stop or tab close. Document this IDEA-vs-process difference in UI copy if needed (optional). Optional later: detect idle prompt — out of scope.

**Stop:** write interrupt (`0x03`) to the bound entry’s PTY; mark session `exited`. Do not dispose the tab.  
**Restart:** Stop (if `running`/`starting`), then inject again into the same bound tab (when `allowMultipleInstances` is false).

### Rerun dialog vs `allowMultipleInstances`

| `allowMultipleInstances` | When selection already has a running lightweight/process session |
|--------------------------|-------------------------------------------------------------------|
| `false` | Offer **Restart** only (no “New instance”) |
| `true` | Allow **Restart** or **New instance** (new tab + new lightweight session in terminal mode; new Run page in non-terminal mode) |

### Terminal mode (`executeInTerminal: true`)

1. Resolve owning folder `targetId` (unchanged RunTargetResolver rules).
2. If `activateToolWindow`: show workspace bottom dock and select **Terminal** tab.
3. **Bind key:** `(workspaceId, selectionKey)` where `selectionKey` is the existing Run selection key (`targetId|folderPath|configId` or equivalent). Do not key only on `(workspaceId, configId)`.
4. **Tab policy:**
   - `allowMultipleInstances == false`: reuse the Terminal entry bound to that key if still alive; else create.
   - `allowMultipleInstances == true` (new instance): always create a new entry and bind that instance’s session to the new entry id.
5. New entry: interactive shell via `WorkspaceTerminalWorkspaceTargetSpec` (or equivalent) for the **owning folder’s `targetId`**, `cwd` = expanded working directory, title derived from config `name` — not the workspace’s generic default-entry target.
6. Connect; wait until transport is ready for I/O using the **same readiness gate** as manual Terminal connect (`transportReadyForIo` / connect-coordinator completion). Default timeout **30s**; on timeout fail the lightweight session.
7. Inject via `TerminalSession.input.writeToPty`.
8. If `focusToolWindow`: focus the terminal view for that entry.

### Tab close while running

If the user closes a Terminal tab that is bound to a lightweight `RunSession` still in `starting`/`running`:

1. Clear the bind-map entry.
2. Mark that `RunSession` `exited` (no separate confirm dialog required beyond normal tab close). Prefer **not** sending Ctrl+C after dispose if the PTY is already torn down.
3. Compounds: remaining members keep their own policy; aggregate failures per parent compound rules.

### Non-terminal mode (`executeInTerminal: false`)

- Assemble equivalent argv / shell command and run through existing `ProcessRunExecutor` + `RunSessionManager` + Run panel.
- `activateToolWindow` / `focusToolWindow` apply to the **Run** surface instead of Terminal.
- Stop/Restart keep existing process-kill semantics and exit-code observation.

### Parallelism and compounds

- Multiple different configs may run in parallel (existing Run platform).
- **Compounds:** each member starts independently. Terminal members each open/reuse tabs per their own `allowMultipleInstances` / bind key; each registers its own lightweight session. `activateToolWindow` from any member may reveal Terminal (or Run for non-terminal members). Failures aggregate with existing compound best-effort policy. Closing one terminal tab exits only that member’s session.

## Architecture

### New / changed components

| Component | Responsibility |
|-----------|----------------|
| `ShellScriptLaunchSchema` | Built-in schema + defaults; replaces user-facing `ProcessLaunchSchema` |
| `ShellScriptCommandBuilder` | Expand fields → injectable / executable command |
| `ShellScriptLauncher` | Branch terminal vs process path from `RunPlatform.start` |
| `WorkspaceTerminalRunService` | Open/reuse Terminal entry, wait ready, inject, interrupt; binds `selectionKey` → entry ids |
| `LaunchTypeRegistry` | Register `shellScript`; treat `process` as alias |
| `RunCubit` / toolbar | Type picker on add; Stop routes interrupt for terminal-backed sessions; rerun dialog respects `allowMultipleInstances` |
| Bottom dock | Activate Terminal vs Run per config flags |

### Hard boundaries

| Core owns | Extensions own |
|-----------|----------------|
| Shell Script schema + terminal inject | All other `launch-type`s |
| Tab bind map for shellScript terminal runs | Adapter I/O |
| Migration from `process` | — |

Workspace Terminal UI remains the owner of PTY theme/connect; the service calls the same create/connect primitives the panel uses (extract shared API; do not duplicate SSH/WSL launch plans).

### Relationship to prior design

Updates the Run platform built-in story (parent doc’s “built-in `process`” / “Run pages only” wording is **superseded for the built-in type** by this spec; amend parent with a short cross-link when convenient):

- Built-in type is **Shell Script**, not `process`.
- Bottom **Run** pages remain for adapter types and `executeInTerminal: false`.
- Workspace Terminal is no longer only a sibling: Shell Script **may** drive it via inject.
- Terminal-backed runs still appear in `RunSessionManager` as lightweight sessions.

## UI

- **Add configuration:** choose type first (Shell Script + extension types), then editor form.
- **Editor form:** AppForm fields matching the schema (file vs text toggle, path pickers, env editor, checkboxes for the four IDEA toggles we support).
- **Type label:** localized “Shell Script” / 「Shell 脚本」.
- Do not surface `process` in the type picker.

## Error handling

| Scenario | Behavior |
|----------|----------|
| Missing script path / empty script text | Schema validation blocks Run |
| Interpreter missing on target | Fail with clear l10n; no silent fallback beyond documented default |
| Terminal connect failed | Lightweight session → `failed` + `errorMessage`; same class of error as manual Terminal open |
| Transport not ready within 30s | Lightweight session → `failed`; no inject |
| Inject write failed | Lightweight session → `failed` |
| Tab closed while bound + running | Clear binding; mark session `exited` |
| Non-terminal spawn failure | Existing Run session `failed` path |

## Testing

- Unit: field defaults; deterministic `process` → `shellScript` migration (shell true/false cases); command builder quoting for file and text modes.
- Unit: tab policy (reuse vs multiple) and bind key with fake registry.
- Unit: rerun dialog options vs `allowMultipleInstances`.
- Unit/widget: activate/focus flags select Terminal vs Run dock.
- Integration-style (mocked PTY): inject after ready; timeout path; Stop sends interrupt; tab close exits lightweight session.
- Regression: extension launch-types, compounds mix, and `executeInTerminal: false` still use Run panel / process kill.

## Success criteria

- User can add a Shell Script config with IDEA-like fields, Run, and see the command execute in an interactive workspace Terminal tab by default (`executeInTerminal: true`).
- `allowMultipleInstances` false reuses the bound tab and Restart-only; true opens a new tab each new instance.
- `executeInTerminal: false` still shows output in the Run panel with stop/kill.
- Existing `process` configs load via the deterministic migration and still run (defaulting to non-terminal to preserve prior semantics).
- Extensions still contribute additional types via the type picker.
- Top-bar Stop works for terminal-backed runs via lightweight `RunSession`.

## Open implementation choices (fix in plan)

1. Exact `scriptText` invocation shape (`interpreter -c …` quoting details; prefer `-c` over temp file/stdin unless blocked on a target).
2. Fine-grained `cd` / `export` layout on the inject line when the tab was already created in the correct `cwd`.
