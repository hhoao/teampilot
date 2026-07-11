# Workspace Run Platform

**Date:** 2026-07-11  
**Status:** Draft  
**Owner decision:** Build a VS Code/IDEA-style **Run** platform (not full Debug in v1) with per-folder `.teampilot/launch.json`, a thin core `RunPlatform`, extension-contributed `launch-type` effects + out-of-process **Launch Adapter** protocol, built-in `process` type, execution on each config’s owning folder `targetId` (local / WSL / SSH), top-bar Run controls, bottom Run terminal pages, and parallel sessions. Prefer best architecture / UX / extensibility over backward compatibility or minimal scope. Steal Launch Provider *concepts* from Lumide; do **not** adopt Lumide’s in-host Dart plugin SDK as the execution model.

## Problem

TeamPilot already has rich **agent session launch** (launch profiles, CLI presets, PTY per member) and an interactive **workspace shell** terminal, but no IDE-style way to configure and run arbitrary workspace programs (API servers, Flutter apps, scripts) with a config dropdown, one-click start/stop, and extension-pluggable runtimes.

Today’s extension system only contributes agent CLI `settings-hook` and `mcp-server` effects. There is no contribution point for run configurations, no launch config file, and no debug/run adapter boundary. Users cannot get an IDEA/VS Code-like Run experience, and language/framework support cannot be added without growing core.

## Goals

- First-class **Run** for workspace programs, separate from agent/team session launch.
- Per-folder **`.teampilot/launch.json`** as the source of truth (git-friendly); dropdown merges across workspace folders.
- Core stays thin: config store, type registry, session manager, terminal bridge, target resolver.
- Extensions adapt via **`launch-type`** effects: schema, adapter binary, discover, kinds, dynamic options, action items.
- Out-of-process **Launch Adapter** JSON-RPC protocol (extensible toward Debug later).
- Built-in **`process`** type so a command can run without installing a language extension.
- Execution follows the **owning folder’s `targetId`** (local / WSL / SSH); adapters run on that target only (`adapter.runtime: workspace`).
- Top-bar config selector + Run/Stop; bottom panel Run pages; **parallel** sessions and compounds.
- Extension discover can **recommend** configs; user accept writes that folder’s `launch.json`.

## Non-goals

- Full Debug (breakpoints, stack, variables, DAP) in v1 — protocol may advertise `supportsDebug` later.
- VS Code `.vscode/launch.json` compatibility or import (may be a later extension concern).
- In-host Dart/JS plugin runtime (Lumide-style `lumide_api` host APIs).
- Tasks/`tasks.json` build system as a separate product surface.
- Changing agent launch profiles, TeamBus, or CLI registry launch contributions.
- Shipping first-party Flutter/Node/… adapters in core (those are extensions).
- Dual storage (app-private override layer) — workspace file only for v1.

## Decision

**Approach: Run Platform + Launch Adapter Protocol.**

```text
UI (top-bar Run + bottom Run terminals)
  → RunPlatform
       LaunchConfigStore (per-folder .teampilot/launch.json)
       LaunchTypeRegistry (process + extension launch-types)
       RunSessionManager (parallel sessions / compounds)
       RunTerminalBridge
       RunTargetResolver (per-folder path + targetId)
  → built-in process spawn on folder target
     OR Launch Adapter process (JSON-RPC on that same target)
```

Rejected alternatives:

| Alternative | Why not |
|-------------|---------|
| Declarative command templates only, adapters optional | Two execution paths; complex types still need adapters; long-term messier |
| Full DAP from day one | Overweight for Run-first; painful fit with existing PTY/terminal model |
| Lumide in-host plugin SDK | Conflicts with declarative extensions + SSH/WSL; huge host API surface |

Reference (concepts only): [lumide_api](https://github.com/SoFluffyOS/lumide_api) Launch Providers; [lumide_flutter](https://github.com/SoFluffyOS/lumide_flutter) as a product bar for a future Flutter extension — not a dependency.

## Architecture

### Hard boundaries

| Core owns | Extensions own |
|-----------|----------------|
| `launch.json` format, UI, shortcuts | Field semantics for a given `type` |
| Select / start / stop / parallel sessions | Turning config into a real process |
| Wiring I/O to Run terminals | Project discover / recommended configs |
| Starting adapters on the correct runtime | Adapter binary itself |
| Built-in `process` | All other types |

### Components (expected code areas)

| Component | Responsibility |
|-----------|----------------|
| `LaunchConfigStore` | Read/write/watch each folder’s `.teampilot/launch.json`; merge + variable expansion |
| `LaunchTypeRegistry` | Register built-in `process` + enabled extension types; conflict detection |
| `RunSessionManager` | Session lifecycle, compounds, stop/restart |
| `RunTerminalBridge` | Map session output ↔ bottom Run pages |
| `RunTargetResolver` | Map config → owning folder path + `targetId` → transport |
| `LaunchAdapterClient` | Spawn adapter on target, JSON-RPC, timeouts |
| `RunCubit` (per workspace) | Selected `(folder, configId)`, options snapshot, sessions — **not** `ChatCubit` |

### Config format (`.teampilot/launch.json`)

**Multi-folder rule:** each `WorkspaceFolder` may own its own `.teampilot/launch.json` at that folder’s root. The Run dropdown **merges** configs from all workspace folders, tagging each entry with its owning folder (path + `targetId`). There is no separate workspace-level launch file outside folders.

**Owning folder = execution context:**

| Concern | Rule |
|---------|------|
| File location | `{folder.path}/.teampilot/launch.json` |
| `${workspaceFolder}` | Expands to that owning folder’s `path` (on the folder’s target filesystem) |
| Run target | Always that folder’s `targetId` (`local` / `wsl:*` / `ssh:*`) — never another folder’s machine |
| Mixed workspaces | Folder A on SSH and folder B local may both contribute configs; each run stays on its owner’s target |

If a folder has no `launch.json`, it simply contributes nothing. Discover runs per folder (globs relative to that folder).

Single JSON file per folder, versioned.

```json
{
  "version": 1,
  "configurations": [
    {
      "id": "api-dev",
      "name": "API (dev)",
      "type": "process",
      "request": "launch",
      "cwd": "${workspaceFolder}",
      "command": "npm",
      "args": ["run", "dev"],
      "env": { "NODE_ENV": "development" }
    }
  ],
  "compounds": [
    {
      "id": "full-stack",
      "name": "Full stack",
      "configurations": ["api-dev", "other-id"]
    }
  ]
}
```

Rules:

- `version` — file schema; platform accepts known versions only.
- `id` — stable within its owning file; UI/session selection key is **`(owningFolder, configId)`** (bare `id` alone is not unique across folders). Fill on write if missing.
- `name` — top-bar label.
- `type` — must be registered.
- `request` — v1 only `launch` (reserve `attach`).
- Type-specific fields validated by that type’s JSON Schema; unknown fields passed through to the adapter.
- Variables: at least `${workspaceFolder}`; also `${env:NAME}`.
- `compounds` — `configurations` lists are **same-file** `id` refs only; start those configs in parallel; default failure policy: best-effort continue + aggregate errors.
- Discover suggestions are **not** persisted until the user accepts.

### Extension contribution (`effects` kind: `launch-type`)

Extends the existing declarative extension manifest alongside `settings-hook` and `mcp-server`. No in-app script plugin host.

Illustrative effect:

```json
{
  "kind": "launch-type",
  "type": "flutter",
  "displayName": "Flutter",
  "kinds": ["run"],
  "adapter": {
    "command": "${extensionPath}/bin/flutter-launch-adapter",
    "lifecycle": "sticky",
    "runtime": "workspace"
  },
  "configurationSchema": { "type": "object", "required": ["device"], "properties": { "device": { "type": "string" } } },
  "discover": { "enabled": true, "globs": ["pubspec.yaml"] }
}
```

Platform behavior:

- Register `type` when the extension is enabled and `detect` passes.
- Validate configs with `configurationSchema` before write/run.
- Resolve `${extensionPath}` relative to the extension install on the **run target** (see `adapter.runtime` below).
- Discover via globs and/or adapter `discover` **per owning folder**; UI shows recommendations; accept writes that folder’s `launch.json`.
- Duplicate `type` from two extensions → error / disable the later one; no silent override.
- Enablement follows existing global → team → workspace extension overrides.
- Strengthened contribution surface (Lumide-inspired): `kinds` (v1: `run`; reserve `debug` / `attach` / `test`), dynamic **options** (device dropdowns, etc.), and **`isAction`** list items (e.g. “Select entry…”).

**`adapter.runtime` (v1):** only `workspace` is allowed — the adapter executable must run on the same `targetId` as the owning folder. There is no `host` mode in v1 (forbids “IDE-local adapter driving a remote tree”). If the adapter binary is not present/runnable on that target, the type is **unavailable** for configs owned by that folder, with an explicit reason.

**Remote adapter provisioning:** out of scope for v1. Extension install remains desktop-local today; SSH/WSL folders do not auto-push adapters. Unavailable type is the correct v1 behavior until a remote extension story exists.

Built-in `process`: fixed schema (`command`, `args`, `env`, `cwd`, optional `shell`); platform spawns on the owning folder’s `targetId` through `RunSessionManager` (same UI path as adapter sessions).

### Launch Adapter protocol

- Transport: adapter process on the owning folder’s target; **stdin/stdout = JSON-RPC**; stderr diagnostics only. Exact framing (newline JSON vs Content-Length) is fixed in the implementation plan — one choice for all adapters.
- **Session correlation:** platform allocates `sessionId` on `launch`; every subsequent `output` / `exited` / `error` for that run must carry the same `sessionId`. Sticky adapters may multiplex many sessions on one process; oneshot adapters are one process per `launch`.
- Lifecycle:
  - `sticky` (default): one adapter process per `(type, targetId)` (or tighter key if needed); multiple `launch` calls reuse it until `shutdown` or crash.
  - `oneshot`: new process per `launch`; exit after `exited` / `stop`.
- Platform → adapter: `initialize`, `discover`, `resolveConfiguration`, `provideOptions`, `launch`, `stop`, `restart` (optional), `shutdown`, plus `configureAction` for action items.
- Adapter → platform: `output`, `exited`, `optionsChanged`, `configurationsChanged`, `error`.
- `initialize` negotiates capabilities: `supportsDiscover`, `supportsOptions`, `supportsStop`, `supportsRestart`, `supportsStdin`, reserved `supportsDebug`.
- Adapters must not call TeamPilot UI APIs. For `isAction` / file picks, the host mediates: UI runs first (picker/dialog), then the platform sends `configureAction` with the user result (wire shapes fixed in the plan; not reverse-RPC from adapter into arbitrary UI).
- Timeouts on `initialize` / `launch`; kill hung processes; adapter crash fails all its sessions.
- v1 I/O: stream via `output` events (optional later `attachPty`). Built-in `process` may support stdin; adapter types default read-only unless `supportsStdin`.

### RunTargetResolver

Resolves **where** a given configuration runs:

1. Determine owning `WorkspaceFolder` from the config’s source `launch.json`.
2. Use that folder’s `path` as `${workspaceFolder}` and default `cwd` base.
3. Use that folder’s `targetId` to select local PTY, WSL, or SSH transport (same family of resolution as workspace shell launch plans).
4. Never substitute a different folder’s target, even if the active editor file lives elsewhere — override only if a future explicit `targetId` field is added to the config (not in v1).

### UI and data flow

**Top bar:** configuration dropdown (merged per-folder `launch.json` + unsaved recommendations + `isAction` items), inline dynamic options, Run / Stop, same-config re-run prompts Restart vs new instance, open `launch.json`, refresh discover.

**Open `launch.json`:** opens the **selected config’s owning file**. If nothing is selected, prompt which workspace folder’s file to open/create.

**Bottom panel:** Run page group beside Terminal; one page per `RunSession` (title = config name; running / exited styling). Closing a running page confirms and may stop the session.

**Flow:**

```text
Run click
  → load config + expand variables (owning folder)
  → schema validate
  → resolve folder targetId
  → process? spawn : adapter initialize/launch
  → register session + focus Run page
  → output / exited update UI
```

State lives in per-workspace `RunCubit` (or equivalent). Recent selection is `(owningFolder, configId)` in local UI state (not necessarily git-tracked). Shortcuts integrate with the existing shortcuts platform (Run / Stop / Restart). Compounds open multiple pages; stopping a compound stops the group.

### Error handling

| Scenario | Behavior |
|----------|----------|
| Missing / empty `launch.json` | Top bar usable; guide add config or accept discover |
| Unregistered / disabled type | Item disabled with reason |
| Schema failure | Block Run; point at fields; offer open file |
| Adapter start failure / timeout | Session failed; show error; no zombie process |
| Adapter crash | All its sessions exited + error |
| Non-zero process exit | Normal `exited`; tab error styling; no modal by default |
| Partial compound failure | Keep successful sessions; aggregate failures |
| Backend cannot execute | Same clarity as workspace shell failures |

User-facing errors via l10n; protocol/adapter diagnostics via `AppLogger` (no `print`).

## Testing

- Unit: parse/expand/validate `launch.json`; registry conflicts; session manager parallel + stop.
- Protocol: fixture fake adapter covering initialize → launch → output → exited / stop.
- Built-in `process`: short local command; mocked transport for WSL/SSH target selection.
- Cubit/UI: select config, create session, stop, restart dialog.
- Extension: parse `launch-type` effect; enablement filtering.
- Out of scope here: real device/Flutter integration (belongs with a Flutter adapter extension).

## Relationship to existing systems

| Existing | Relationship |
|----------|----------------|
| Launch profiles / `SessionLifecycleService` | Unchanged; agent launch only |
| `WorkspaceTerminalRegistry` / shell | Sibling bottom panel; Run pages are separate sessions |
| Extension install (desktop-local today) | Run requires adapter on workspace target; SSH gaps surface as unavailable type |
| Shortcuts platform | New commands: Run / Stop / Restart |
| Editor / workbench | Open selected config’s owning `launch.json`; no agent-tab coupling |

## Success criteria

- User can add a `process` config in a folder’s `.teampilot/launch.json`, Run from the top bar, see output in a bottom Run page, Stop, and run two configs in parallel.
- A sample extension can register a `launch-type`, pass `detect`, recommend a config via discover, and run through a fixture adapter.
- For a config owned by an SSH (or WSL) folder, a type whose adapter is missing on that target is disabled with an explicit reason — never silently runs on the IDE host against remote sources. Remote adapter provisioning is out of scope for v1.
- Agent session launch UX and APIs remain unaffected.
