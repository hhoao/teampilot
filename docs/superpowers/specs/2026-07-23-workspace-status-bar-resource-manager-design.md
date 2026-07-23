# Workspace status bar + Resource Manager

## Goal

Add an Orca-style **workspace bottom status bar** with an extensible item registry. First item: **Resource Manager** — a closed pill (total memory · terminal count) that opens a popover tree of terminals with CPU / memory, refresh, and kill actions.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Parity | Align Orca Resource Manager UX (pill + tree + CPU/Mem + kill/refresh) |
| Placement | App-global on `HomeShell` (all workspaces’ sessions); flush window bottom |
| Status bar shape | Extensible `WorkspaceStatusBar` shell; v1 ships only `resource-usage` |
| Remote / SSH | Rows still appear; CPU/Mem show `—`; navigate + kill still work |
| Disk "Space" | Footer stub with Beta + “does not scan workspace disk usage”; no scanner in v1 |
| Platform | Desktop local metrics via host process listing; Android shows bar + tree, local metrics best-effort / `—` when PID or sweep unavailable |

## Non-goals (v1)

- Additional status segments (ports, SSH, updates, pets, provider usage)
- Real workspace disk Space scan
- Remote SSH `ps` over the tunnel
- Orphan daemon / worktree cleanup flows unique to Orca’s Electron daemon model
- Killing the Flutter app process itself from the panel

## Product UX

### Closed pill (`resource-usage`)

- Right cluster of the workspace status bar (bottom-right of the workbench card).
- Content: memory icon + formatted total tracked memory (or `—`) · terminal icon + **bound terminal count** for this workspace.
- Tooltip: `Resource Manager - {memory} - {n} terminals` plus one-line hint that sessions are grouped by worktree / session.
- Closed-state terminal count comes from **in-memory registries only** (no host `ps` sweep). Memory badge uses the **last successful snapshot** when available; otherwise `—`.
- Do **not** poll host process metrics while the popover is closed.

### Open panel

Popover anchored above the pill (Orca-like), via `TpActionMenuAnchor`:

**Chrome / layout (Orca `ResourceUsageStatusSegment` parity):**

- **Gap:** `TpAnchor` opens upward with **8px** between pill and panel (`sideOffset={8}` equivalent).
- **Width:** `416` (`w-[26rem]`).
- **Structure** (top → bottom):
  1. **Header** (intrinsic): “Resource Manager - Sessions” + refresh + kill-all.
  2. **Totals row** (intrinsic): aggregate CPU %, memory, host memory share, sparkline.
  3. **Optional App bucket** (intrinsic or inside scroll when present): Flutter / Dart VM process when collectable.
  4. **Fixed body `420` logical px** (does not grow/shrink with session count — avoids popover jump):
     - Column headers Name | CPU | Memory (fixed, outside scroll).
     - **Scrollable** tree: workspace/worktree groups → running leaf rows only.
     - Empty: “Nothing running…” still fills the scroll region inside the fixed body.
  5. **Space stub** (intrinsic, **outside** the 420 body): drive icon, “Space”, Beta, no-scan copy.

**Tree / leaf behavior:**

- Tree depth: group → leaf only; session/member identity in the leaf label.
- Leaf: green connected dot, title, kill, click navigates.
- Remote / missing metrics: `—`.
- Idle / disconnected shells omitted from inventory.

### Polling

- While popover **open**: refresh snapshot every **2s**, coalesce concurrent collects onto one in-flight sweep.
- On open: immediate snapshot + rebuild tree.
- After kill / kill-all: refresh tree bindings immediately; next metrics tick fills CPU/Mem.

## Architecture

```
WorkspacePage
 └─ Column(
      Expanded(existing workbench body),
      WorkspaceStatusBar(
        items: [ResourceUsageStatusItem, …future],
      ),
    )

ResourceManagerCubit
  ← ChatCubit / WorkspaceTerminalRegistry / worktree registry (bindings)
  ← PtyProcessRegistry (pid ↔ transport id)
  ← ProcessMetricsService.collectSnapshot(registeredPids)
  → ResourceManagerState (open, snapshot, tree VM, errors)
```

### Layers

| Unit | Responsibility |
|------|----------------|
| `WorkspaceStatusBar` | Thin strip; renders registered `WorkspaceStatusBarItem`s; layout right-cluster first |
| `WorkspaceStatusBarItem` | Id + builder for closed segment (+ optional open overlay ownership) |
| `ResourceUsageStatusItem` | Pill + owns Resource Manager popover |
| `ResourceManagerPanel` | Tree UI, totals, header actions, Space stub |
| `ResourceManagerCubit` | Open/close, poll timer, merge bindings + snapshot → view model, dispatch kill/navigate |
| `PtyProcessRegistry` | Register/unregister local PTY pids when transports connect/dispose |
| `ProcessMetricsService` | Host memory + per-pid subtree CPU/RSS via platform process listing; coalesced |
| Merge helpers | Pure functions: bindings + snapshot → grouped tree rows (unit-tested) |

### PID plumbing

`flutter_pty_new` already exposes `Pty.pid`. Thread it up:

`Pty` → `LocalPtyTransport.pid` → `TerminalTransport` optional `int? get pid` → `TerminalSession` / registry on connect.

`SshPtyTransport.pid` stays `null`. Registry only tracks local pids.

On connect: register `(bindingKey, pid)`. On dispose/disconnect: unregister.

### Bindings (closed count + tree identity)

For the **active workspace id**, collect:

| Kind | Source | Display |
|------|--------|---------|
| Chat member shells | `ChatCubit` tabs/sessions for this workspace → `memberShells` | Session title + member/replica label |
| Workspace shell PTYs | `WorkspaceTerminalRegistry` group for this workspace | Shell tab title |

Group by worktree id when the session/shell has one; otherwise a single “main” (or primary project folder) group.

**Running session count** = number of leaf bindings with a live connected shell (`isConnected` / `isRunning`), not host process count and not idle/disconnected tabs.

### Metrics snapshot (desktop)

Analogous to Orca `MemorySnapshot`, scoped to TeamPilot:

```text
ResourceMemorySnapshot
  host: total / free / used / percent / cpuCores / load1m (best-effort)
  app: optional Flutter process usage + short memory history ring
  groups[]: worktreeKey, name, aggregate cpu/mem, history[] (for sparklines — **in v1 UI**), leaves[]
  leaves: bindingKey, pid?, cpu?, memoryBytes?, connected
  totalCpu / totalMemory (app + tracked leaves that have values)
  collectedAt
```

v1 **includes** sparklines in the open panel (totals, group rows, optional app row) fed by these history rings.
Collection:

- One host-wide process table (`ps` on Linux/macOS, `wmic`/`Get-CimInstance` on Windows) with timeout + max buffer.
- For each registered pid, sum CPU/RSS over the process **subtree** (pid + descendants via ppid).
- Missing pid or failed parse → leaf metrics null → UI `—`.
- Coalesce overlapping `collect()` calls.
- Never run the sweep from UI isolates that block frames; keep async and cache last good snapshot.

### Actions

| Action | Behavior |
|--------|----------|
| Refresh | Force `collect()` + rebuild tree |
| Kill leaf | Existing session/shell disconnect/kill path for that binding |
| Kill all | Kill every leaf binding in the current workspace tree (confirm dialog) |
| Navigate | Focus workspace session / shell; for chat members **preserve** the session’s current `SessionWorkbenchView` (chat or terminal); close popover |
| Space stub | Non-interactive info row (or disabled expand) — no scan |

Kill must go through existing lifecycle APIs (`TerminalSession` / registry), not raw `Process.kill` alone, so chat/workspace state stays consistent. Optional: after lifecycle kill, best-effort `Process.killPid` if the process remains.

## Status bar extensibility

- Item ids are stable strings (`resource-usage`, …).
- v1 hard-codes the visible list to `[resource-usage]`; do not build a full settings editor for toggling items yet, but keep the item interface so later segments plug in without redesigning the strip.
- Compact / icon-only mode: when the workbench is narrow, pill may drop labels and keep icons + truncated values (match Orca compact behavior where cheap).

## Placement / layout

- Mount on **`HomeShell`** as an app-global strip at the **window bottom**, via `GlobalResourceManagerHost` — visible on home library and every workspace tab.
- Status strip is **transparent** on the page chrome (no fill / top rule); the floating card omits bottom inset, and the strip itself uses a small vertical inset (~4px) above and below so it is not flush to the card or window edge (corners stay rounded).
- Terminal / session inventory spans **all workspaces** (tree groups by workspace display name).
- Height: compact content row (~20 logical px) plus vertical inset — not a second title bar.
- Does not replace `WorkspaceTerminalPanel` or Run toolbar; those stay as today.

## Error handling

- Snapshot failure: keep last good snapshot; show a subtle error affordance in the open panel header; pill falls back to `—` for memory if never succeeded.
- Kill failure: toast via existing `AppToast` / l10n; leave row in place until registries update.
- Unsupported platform sweep: tree still works; all metric cells `—`.

## Testing

- Pure merge: bindings + snapshot → tree groups/leaves, aggregates, `—` for null metrics.
- Closed count ignores host processes not in bindings; includes only running (connected) shells.
- Polling: open starts timer; close cancels; workspace change closes + cancels.
- PID registry: register on local connect, clear on dispose; SSH never registers.
- Cubit kill-all calls lifecycle for each leaf once.
- Widget: pill shows count from fake cubit; panel columns render `—` when metrics null.
- No integration test required for live `ps` in CI; collector parsing covered with fixture process tables.

## Implementation notes

- Prefer `client/lib/widgets/workspace_status_bar/` for chrome and `client/lib/services/resource_manager/` (or `process_metrics/`) for collector + registry — not the existing skill/plugin “resource” package.
- l10n: `app_en.arb` / `app_zh.arb` for all user-visible strings (Resource Manager, columns, Space stub, tooltips, kill confirm).
- Follow `docs/CODE_QUALITY.md` layering: no `Process.run` in widgets; inject collector into cubit.
- File-size soft limits: split panel tree, merge, and collector platform backends if any file grows large.
- Visual language: Tp dark surfaces, green connected dots, popover elevation consistent with existing menus — emulate Orca information architecture, not pixel-copy Electron chrome.
