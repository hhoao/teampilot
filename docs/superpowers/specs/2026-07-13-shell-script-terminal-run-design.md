# Shell Script Terminal Run (IDEA-aligned)

**Date:** 2026-07-13  
**Status:** Draft  
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
- Migrate existing `type: "process"` entries on read (compat alias).
- Extract a small **`WorkspaceTerminalRunService`** so Run does not reach into panel-private methods.

## Non-goals

- Before launch / Tasks system (still out of scope per Run platform non-goals).
- “Show this page before run.”
- Full Debug / DAP.
- Replacing extension Launch Adapter types or the Run panel for adapter/`executeInTerminal: false` sessions.
- Shipping first-party language adapters in core.
- Perfect Windows interpreter discovery in v1 (sensible defaults + explicit path field are enough).
- Prompt heuristics beyond “PTY transport ready” for injection timing (no ANSI prompt scraping in v1).

## Decision

**Approach A: Terminal inject after connect**, with IDEA-shaped config toggles.

```text
Run ▶ (type shellScript)
  → expand + validate Shell Script fields
  → build command line (interpreter + options + script + script options)
  → if executeInTerminal:
       WorkspaceTerminalRunService.openOrReuse(configKey)
         → ensure Terminal tab (cwd, default shell for folder target)
         → wait transport ready
         → session.input.writeToPty(command + CR)
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

## Config model

### Type identity

| Wire `type` | Role |
|-------------|------|
| `shellScript` | Canonical built-in type |
| `process` | Read-only alias → normalize to `shellScript` on load; writers emit `shellScript` |

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
| Execute in the terminal | `executeInTerminal` | `true` | |
| Activate tool window | `activateToolWindow` | `true` | Reveal bottom dock + Terminal (or Run) |
| Focus tool window | `focusToolWindow` | `false` | Request focus on that surface |
| Show this page | — | — | Non-goal |
| Before launch | — | — | Non-goal |

### `process` migration

On load, if `type == "process"`:

| Old field | Maps to |
|-----------|---------|
| `command` | `interpreterPath` (or treat whole line as script-text if `shell: true` and no clear split — prefer: `interpreterPath` = command, `scriptOptions`/args from `args`) |
| `args` | Joined into `scriptOptions` **or** keep as structured args only on non-terminal path |
| `shell: true` | Prefer `execute: scriptText` with `scriptText` = command string; interpreter = `/bin/sh` (or `/bin/bash`) |
| `cwd` / `env` | Same |
| — | `executeInTerminal: true`, `allowMultipleInstances: false` |

Exact mapping rules are fixed in the implementation plan; goal is zero data loss for common configs and writers always saving `shellScript`.

## Runtime behavior

### Command assembly

Conceptual line injected / executed:

```text
cd <cwd> && <interpreterPath> <interpreterOptions…> <scriptPath|inline> <scriptOptions…>
```

Rules:

- Quote paths/args safely for the target shell (local / WSL / SSH).
- For `scriptText`, pass text to the interpreter in an IDEA-compatible way (e.g. `bash -c '…'` or interpreter reading stdin — choose one in the plan and test both quoting edge cases).
- Prefer a single injectable line ending with `\r` for terminal mode.

### Terminal mode (`executeInTerminal: true`)

1. Resolve owning folder `targetId` (unchanged RunTargetResolver rules).
2. If `activateToolWindow`: show workspace bottom dock and select **Terminal** tab.
3. **Tab policy:**
   - `allowMultipleInstances == false`: reuse the Terminal entry bound to `(workspaceId, owningFolder, configId)` if still alive; else create.
   - `allowMultipleInstances == true`: always create a new entry.
4. New entry: default interactive shell for that folder target (same catalog as “+” Terminal), `cwd` = expanded working directory, title derived from config `name`.
5. Connect; when transport is ready for I/O, inject the command line via `TerminalSession.input.writeToPty`.
6. If `focusToolWindow`: focus the terminal view for that entry.
7. **Stop:** inject interrupt (`Ctrl+C` / `0x03`) to that entry’s PTY. Do not dispose the tab unless the user closes it. Restart = Stop then inject again (reuse policy still applies).

**Env in terminal mode:** v1 best-effort — prefix `VAR=value` on the injected line and/or rely on shell already having workspace env; do not require rewriting login-shell spawn. Document limitation if full `env` map cannot be applied without `export` prefix.

### Non-terminal mode (`executeInTerminal: false`)

- Assemble equivalent argv / shell command and run through existing `ProcessRunExecutor` + `RunSessionManager` + Run panel.
- `activateToolWindow` / `focusToolWindow` apply to the **Run** surface instead of Terminal.
- Stop/Restart keep existing process-kill semantics.

### Parallelism

- Multiple different configs may run in parallel (existing Run platform).
- Same config: if `allowMultipleInstances` is false and a terminal tab is already bound, reinject into that tab (user may still have a previous command running — same as IDEA reuse risk). If true, each Run opens another tab / another Run session (non-terminal).

## Architecture

### New / changed components

| Component | Responsibility |
|-----------|----------------|
| `ShellScriptLaunchSchema` | Built-in schema + defaults; replaces user-facing `ProcessLaunchSchema` |
| `ShellScriptCommandBuilder` | Expand fields → injectable / executable command |
| `ShellScriptLauncher` | Branch terminal vs process path from `RunPlatform.start` |
| `WorkspaceTerminalRunService` | Open/reuse Terminal entry, wait ready, inject, interrupt; binds config keys → entry ids |
| `LaunchTypeRegistry` | Register `shellScript`; treat `process` as alias |
| `RunCubit` / toolbar | Type picker on add; stop routes interrupt for terminal-backed runs |
| Bottom dock | Activate Terminal vs Run per config flags |

### Hard boundaries

| Core owns | Extensions own |
|-----------|----------------|
| Shell Script schema + terminal inject | All other `launch-type`s |
| Tab bind map for shellScript terminal runs | Adapter I/O |
| Migration from `process` | — |

Workspace Terminal UI remains the owner of PTY theme/connect; the service calls the same create/connect primitives the panel uses (extract shared API; do not duplicate SSH/WSL launch plans).

### Relationship to prior design

Updates the Run platform built-in story:

- Built-in type is **Shell Script**, not `process`.
- Bottom **Run** pages remain for adapter types and `executeInTerminal: false`.
- Workspace Terminal is no longer only a sibling: Shell Script **may** drive it.

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
| Terminal connect failed | Fail run; show same class of error as manual Terminal open |
| Inject before ready | Wait for transport ready with timeout; then fail |
| Tab closed while “bound” | Clear binding; next Run creates a new tab |
| Non-terminal spawn failure | Existing Run session failed path |

## Testing

- Unit: field defaults; `process` → `shellScript` migration; command builder quoting for file and text modes.
- Unit: tab policy (reuse vs multiple) with fake registry.
- Unit/widget: activate/focus flags select Terminal vs Run dock.
- Integration-style (mocked PTY): inject called once after ready; Stop sends interrupt.
- Regression: extension launch-types and `executeInTerminal: false` still use Run panel.

## Success criteria

- User can add a Shell Script config with IDEA-like fields, Run, and see the command execute in an interactive workspace Terminal tab by default.
- `allowMultipleInstances` false reuses the bound tab; true opens a new tab each Run.
- `executeInTerminal: false` still shows output in the Run panel with stop/kill.
- Existing `process` configs continue to load and run after migration mapping.
- Extensions still contribute additional types via the type picker.

## Open implementation choices (fix in plan)

1. Exact `scriptText` invocation (`-c` vs temp file vs stdin).
2. How aggressively to `cd` + `export` on the injected line vs spawn shell already in `cwd`.
3. Whether terminal-backed runs appear in `RunSessionManager` as lightweight sessions (for Stop button state) or a parallel “terminal run handle” map — prefer **lightweight RunSession** so the top-bar Stop stays unified.
