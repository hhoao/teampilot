# Terminal Resize Architecture

**Date:** 2026-06-21 (updated 2026-06-22)
**Status:** Partially implemented

## Implementation Status

| Item | Status |
|------|--------|
| `ViewportGeometryResolver` + `TerminalGrid` + `ViewportQuery` | ✅ Implemented + tested |
| `ResizeCommitPolicy` + `StableFrameCommitPolicy` + `ImmediateCommitPolicy` | ✅ Implemented + tested |
| `TerminalResizeController` | ✅ Implemented + tested |
| `TerminalLayoutCoordinator` | ✅ Implemented + tested |
| `TerminalView` integration (optional `resizeController` param) | ✅ Implemented |
| `TerminalSession.attachResizeController` | ✅ Implemented |
| `WorkspaceTerminalPanel` wiring (controller, coordinator, dispose/unregister) | ✅ Implemented |
| `ChatWorkbenchTerminal` wiring (controller reused per-engine, unregister) | ✅ Implemented |
| `ResizableSplitView` divider drag | 🔄 Policy-only — `onDragStart/onDragEnd` are intentionally empty; the 150 ms settle commits at drag end (no transaction bracket) |
| Legacy timer code deleted from `terminal_session.dart` | ⏳ Retained — deprecated `onViewportResize` + `_scheduleLayoutPtyGeometrySettle` (80 ms) kept as a no-op-when-controller-attached fallback for un-migrated callers |
| Sidebar close → coordinator transaction | ✅ Implemented |
| Hit-test / mouse / selection clamp to committed engine grid | ✅ Implemented |
| Resolver pixel-floor guard (48×24 px) | ✅ Implemented |
| Settle-timer + safety-valve (total-frame) test coverage | ✅ Implemented |
| `StableFrameCommitPolicy` default in production | ✅ Implemented |
| Startup race simplified (reads controller.current) | ✅ Implemented |
| Spec updated: status, pseudocode, deviations, file layout | ✅ Implemented |
| Sidebar open/toggle → coordinator transaction | ⏳ Deferred (need LayoutCubit injection) |
| Worktree switch → coordinator transaction | ⏳ Deferred (need WorktreeCubit injection) |
| Tab open/close → coordinator transaction | ⏳ Deferred (need per-tab coordinator scope) |
| Scroll state preserve on resize | ⏳ Future iteration |
| Mobile fit override | ⏳ Future iteration |
| Shared app-level coordinator (vs per-panel) | ⏳ Future iteration |

**Branch:** (none yet)
**Reference implementations:** orca (`src/renderer/src/lib/pane-manager/`), alacritty's `display/mod.rs`

---

## 0. Motivation

The terminal resize pipeline currently mixes measurement, gating, and delivery across two files with four overlapping wall-clock timers. Layout transitions (sidebar collapse, divider drag, worktree switch, tab-open animation) push intermediate grid sizes to the PTY, causing visible "jump" — a TUI re-layouts to the transient size, then re-layouts again when the container settles. The user reports that resize "feels inaccurate."

This is not a measurement-bug. `CellMetrics.measure` measures real rendered cells, the painter uses the same `_metrics.width`/height, and `engine.resize` is authoritative. The root cause is **timing**: the pipeline cannot distinguish a transitional grid from a final one, so it sends everything to the PTY.

This document redesigns the pipeline from scratch — no backwards-compat, no legacy code constraints, no "minimum change."

---

## 1. Reference: orca's fit pipeline

Orca (Electron, xterm.js + WebGL) has the terminal resize pipeline we target. Key elements:

### 1.1 Measurement

`xterm`'s `FitAddon.proposeDimensions()` reads `_renderService.dimensions.css.cell.width/height` — the **renderer's actual measured cell size**, not a separate estimate. `cols = floor(availWidth / cssCellWidth)`.

TeamPilot equivalent: `CellMetrics.measure(style)` is already a renderer-native measurement (TextPainter layout of the actual font, divided by sample count). This part is correct and stays.

### 1.2 Minimum-viable-geometry guard

`pane-tree-ops.ts:30-58` — `canMeasurePaneForFit`:

```typescript
const MIN_PANE_FIT_WIDTH_PX = 48
const MIN_PANE_FIT_HEIGHT_PX = 24
const MIN_PANE_FIT_COLS = 8
const MIN_PANE_FIT_ROWS = 4

function canMeasurePaneForFit(pane): boolean {
  // Container must have non-trivial pixel dimensions
  if (rect.width < 48 || rect.height < 24) return false
  // Proposed grid must meet minimum usable dimensions
  const dims = getProposedDimensions(pane)
  return dims && dims.cols >= 8 && dims.rows >= 4
}
```

**Why 8×4 and not 2×1?** A worktree switch can briefly measure a near-zero overlay before fallback positioning lands. Fitting at that moment pins the PTY at 2 cols until the next user-driven resize. The guard says: "if the container isn't big enough to show a usable terminal, don't resize the PTY."

TeamPilot current: `clamp(kMinTerminalColumns=2, kMinTerminalRows=1)`. This is the VT-engine floor (prevents fullwidth-glyph panic), not the UI floor. It should never reach the PTY.

### 1.3 Stability-frame gating (the core insight)

`pane-fit-resize-observer.ts`:

```
ResizeObserver fires
  → proposeDimensions()
  → wait up to 8 rAF frames
     → each frame: re-read proposeDimensions()
     → if proposal matches current terminal: skip (no-op)
     → if two adjacent frames produce the SAME proposal: safeFit()
     → if 8 frames pass without stability: safeFit() anyway (safety valve)
```

**Why rAF and not wall-clock timers?** The browser's layout cycle determines when dimensions settle. Wall-clock timers either fire too early (during transition) or too late (wasted latency). rAF is per-frame — it fires exactly when layout has finished for that frame, so repeated rAF reads naturally converge when the layout stabilizes.

TeamPilot current: 90ms leading+trailing throttle (`_resizeWindow`) + 80ms layout settle + 80ms output debounce. Three wall-clock timers stacked on top of each other, none aligned with the frame cycle. In Flutter, the equivalent of rAF is `SchedulerBinding.addPostFrameCallback`.

### 1.4 Proposal=current skip

`pane-tree-ops.ts:92-96`:

```typescript
if (dims.cols === pane.terminal.cols && dims.rows === pane.terminal.rows) {
  return  // skip — most divider-drag frames don't cross a cell boundary
}
```

Prevents `fitAddon.fit()` reflow when the grid hasn't actually changed. Orca also notes this prevents "visible terminal blinking while resizing."

TeamPilot equivalent: `terminal_view.dart`'s `_ensureSizing` already skips `cols == _cols && rows == _rows`. But `terminal_engine.dart:191` also has `if (columns == _lastColumns && rows == _lastRows) return`. These are correct and stay.

### 1.5 Layout-transaction hold

`pane-pty-resize-hold.ts`:

```
holdPtyResizesForPaneSubtrees(roots) → { flush, cancel }
  → beginPanePtyResizeHold(each pane): depth++
  → queuePanePtyResizeIfHeld: stores {cols, rows} if held
  → flush: release → dispatch custom event with final {cols, rows}
  → cancel: release without flushing
```

Structural layout changes (split create/destroy, reorder, reparent) bracket their DOM mutations with hold/flush, so the PTY receives **one** resize at the final size instead of a transient sequence.

TeamPilot equivalent (originally none): now implemented as `TerminalLayoutCoordinator`. **Caveat:** it is currently instantiated **per panel** (one in the chat workbench, one in the workspace terminal panel), not as a single app-level singleton — so the two panels can't yet hold each other's PTY resizes jointly. App-level injection is deferred (see the status table). Today the only wired transaction is the workspace panel's "close panel" (sidebar collapse); divider drag relies on the policy's settle, not a transaction bracket.

### 1.6 Synchronous pre-paint fit

`use-terminal-container-fit-sync.ts`:

```
SYNC_FIT_PANES_EVENT dispatched from useLayoutEffect (pre-paint)
  → fitAllPanes() synchronously
  → subsequent ResizeObserver-based fits become no-ops (proposal matches current)
```

**Why?** "Eliminates the ~16ms 'old cols, new container width' flash that a deferred ResizeObserver rAF would otherwise produce." On a sidebar open/close, the container's width changes in the same frame — fitting synchronously before paint means the terminal is already at the correct size when it appears.

TeamPilot equivalent: the current `addPostFrameCallback` in `_syncViewportToHost` is the opposite — it **defers** engine resize by one frame, creating the flash orca eliminates.

---

## 2. Target architecture

Three pure layers + one app-level coordinator. All existing timers, flags, and callback chains in the resize path are deleted.

```
┌───────────────────────────────────────────────────┐
│         TerminalLayoutCoordinator                  │  ← app-level, 1 instance
│  runLayoutTransaction / flushAll / immediateReFit │    (replaces WorkspaceTerminalRegistry
├───────────────────────────────────────────────────┤     resize duties)
│        TerminalResizeController                    │  ← 1 per TerminalView
│  propose(Geometry?) → display commit | PTY commit  │
├──────────────────────┬────────────────────────────┤
│ ViewportGeometryResolver │  ResizeCommitPolicy      │  ← leaf modules, pure/testable
└──────────────────────┴────────────────────────────┘
```

### 2.1 Layer 1 — ViewportGeometryResolver (pure measurement)

```dart
/// The grid that fits a viewport at its current font metrics.
@immutable
class TerminalGrid {
  final int cols;
  final int rows;
  const TerminalGrid(this.cols, this.rows);

  bool get isValid => cols > 0 && rows > 0;

  // Never produce a grid smaller than the "usable" floor.
  static const int minCols = 8;
  static const int minRows = 4;
  static bool isUsable(int cols, int rows) => cols >= minCols && rows >= minRows;
}

/// Parameters needed to resolve the terminal grid for a viewport.
class ViewportQuery {
  /// Available paint area (already has padding subtracted).
  final Size available;

  /// Measured cell dimensions at the current font size + DPR.
  /// Sub-pixel precision; the painter uses the same values.
  final CellMetrics cell;

  /// Space reserved for chrome (scrollbar gutter, etc.).
  /// Subtracted from `available` before cell-grid math.
  final EdgeInsets reserve;

  const ViewportQuery({
    required this.available,
    required this.cell,
    this.reserve = EdgeInsets.zero,
  });
}

/// Pure: no state, no timers, no callbacks.
class ViewportGeometryResolver {
  /// Returns the grid that fits [q], or null when the container is too small to
  /// host a usable terminal (transition frame — do NOT push to PTY).
  TerminalGrid? resolve(ViewportQuery q) {
    final availW = (q.available.width - q.reserve.horizontal).clamp(0, double.infinity);
    final availH = (q.available.height - q.reserve.vertical).clamp(0, double.infinity);

    if (availW <= 0 || availH <= 0) return null;

    final cols = (availW / q.cell.width).floor();
    final rows = (availH / q.cell.height).floor();

    // Usability guard: reject grids too small for a real terminal.
    // This is the counterpart of orca's canMeasurePaneForFit.
    if (!TerminalGrid.isUsable(cols, rows)) return null;

    return TerminalGrid(cols, rows);
  }
}
```

**Design decisions:**
- Returns `null` (not a clamped degenerate grid) when the viewport is too small. The caller decides what to do (typically: keep current grid).
- `minCols=8, minRows=4` — orca's floor. A fullwidth CJK glyph is 2 cols; below 8 you can't show even a short filename.
- `reserve` replaces the hardcoded symmetrix padding pattern. The host (workspace panel, chat workbench) declares how much space its chrome consumes, and the resolver accounts for it.

### 2.2 Layer 2 — ResizeCommitPolicy (strategy)

**API** (matches orca's split between observation and rAF callback):

```dart
typedef PtyResizeCommit = void Function(int cols, int rows);

abstract class ResizeCommitPolicy {
  /// Record a proposal from this frame's layout pass. Called synchronously
  /// inside [LayoutBuilder]. Does NOT commit — that happens in [onFrame].
  void onProposal(TerminalGrid proposed, TerminalGrid current);

  /// Called once per frame after layout (from
  /// `SchedulerBinding.addPostFrameCallback`). The policy may commit now
  /// if its stability criteria are met. This split mirrors orca's rAF
  /// loop where each callback re-reads `proposeDimensions()`.
  void onFrame(PtyResizeCommit commit);

  void flush(TerminalGrid grid, PtyResizeCommit commit);
  void cancel();
}
```

**StableFrameCommitPolicy** (production — see `resize_commit_policy.dart`):

Two-tier convergence matching orca's `pane-fit-resize-observer.ts`:

| Tier | Orca | This spec (as implemented) | Implemented |
|------|------|-----------|-------------|
| **Stability gate** (continuous resize) | 2 adjacent identical proposals → fit | 2 consecutive identical proposals → commit (aligned with orca) | ✅ `_stabilityCount`, `maxStabilityFrames = 2` |
| **Total-frame safety valve** (animated change) | 8 rAF frames max | 8 total frames without the gate firing | ✅ `_frameCount`, `safetyValveFrames = 8` |
| **Settle fallback** (discrete resize) | 150ms container debounce | 150ms settle timer | ✅ `Timer(_settleDuration)` |

The settle timer is a deliberate deviation from the initial "zero wall-clock timers" design goal. It handles discrete resizes (sidebar toggle, maximize, worktree switch) that produce only 1–2 frames then go silent — the stability counter would never converge. The timer is cancelled on every `onProposal`, so it only fires when no more frames arrive. This matches orca's container-level 150ms debounce (`use-terminal-container-fit-sync.ts:56-68`). The old implementation's four stacked timers (90ms + 80ms + 80ms + postFrame) are still eliminated; this is a single fallback at the correct architectural layer.

**`current` semantics:** `onProposal(proposed, current)` receives `_committedPty` (the grid last sent to the PTY), NOT the display grid (`_current`). Before the first commit, `_committedPty` is null; the controller passes `TerminalGrid.sentinel` (65535×65535) so the first proposal is never skipped by a same-size check.

### 2.3 Layer 3 — TerminalResizeController (per-view orchestrator)

This replaces the current `_ensureSizing` + `_syncViewportToHost` + `_applyViewportResize` chain in `terminal_view.dart` and the `onViewportResize` → `_syncPtyGeometryNow` + `_scheduleLayoutPtyGeometrySettle` chain in `terminal_session.dart`.

```dart
/// One per TerminalView. Owns the resize lifecycle for a single terminal pane.
class TerminalResizeController {
  TerminalResizeController({
    required TerminalEngine engine,
    required ResizeCommitPolicy policy,
    ViewportGeometryResolver? resolver,
  })  : _engine = engine,
        _policy = policy,
        _resolver = resolver ?? ViewportGeometryResolver();

  final TerminalEngine _engine;
  final ResizeCommitPolicy _policy;
  final ViewportGeometryResolver _resolver;

  /// Latest PROPOSED grid (the size the viewport could host this frame). Under
  /// lock-step it can LEAD the engine/PTY during a drag; read [committed] for
  /// the authoritative size the subprocess is actually running at.
  TerminalGrid _current = const TerminalGrid(80, 24);
  TerminalGrid get current => _current;

  /// The grid actually committed to the engine + PTY (null before first commit).
  TerminalGrid? get committed => _committedPty;

  /// How many layout-transaction holds are active (nesting-safe).
  int _transactionDepth = 0;

  /// Grid queued during a transaction — flushed on transaction end.
  TerminalGrid? _queuedTransactionGrid;

  /// Whether the controller ran at least one proposal (engine is initialized).
  bool _initialized = false;

  // ── Public API ──────────────────────────────────────────────────────────

  /// Called from TerminalView's LayoutBuilder every frame.
  /// Returns the grid that SHOULD be displayed (always up-to-date).
  /// What happens to the PTY depends on the policy.
  TerminalGrid propose(ViewportQuery query) {
    final proposed = _resolver.resolve(query);

    // Transition frame with unusable geometry: keep current grid.
    // `_current` holds the latest PROPOSED grid (may lead the engine mid-drag).
    final effective = proposed ?? _current;
    _current = effective;

    // ── Engine init only (lock-step: NO per-frame engine.resize) ──
    // The engine is initialized once, at the first real proposal, so it exists
    // before any PTY output arrives. After that it stays at the committed size
    // and is resized ONLY in _commitPty, together with the PTY (see §5bis.1).
    if (!_initialized && proposed != null) {
      _engine.resize(columns: effective.cols, rows: effective.rows);
      _engine.initializeEmpty(effective.rows, effective.cols);
      _initialized = true;
    }

    // ── PTY + engine commit (gated, lock-step) ──
    if (_transactionDepth > 0 && proposed != null) {
      // Structural layout in progress: remember the latest and defer.
      _queuedTransactionGrid = proposed;
    } else if (proposed != null) {
      // Record proposal (current = _committedPty, NOT effective).
      // Before first commit, pass sentinel to force commit regardless of size.
      _policy.onProposal(
        proposed,
        _committedPty ?? TerminalGrid.sentinel,
      );
      _scheduleFrameCallback(); // → post-frame → _policy.onFrame(_commitPty)
    }
    // (proposed == null): transitional frame, skip entirely.

    return effective;
  }

  /// Enter a layout transaction. PTY resizes are queued, not sent.
  /// Nesting-safe: matching endTransaction calls are required.
  void beginTransaction() {
    _transactionDepth++;
  }

  /// End a layout transaction. If this was the outermost, flush the queued grid.
  void endTransaction({bool flush = true}) {
    if (_transactionDepth <= 0) return;
    _transactionDepth--;
    if (_transactionDepth == 0) {
      final grid = _queuedTransactionGrid;
      _queuedTransactionGrid = null;
      if (flush && grid != null) {
        _policy.flush(grid, _commitPty);
      }
    }
  }

  /// Force an immediate commit (font-zoom, manual resize, app startup).
  void commitNow() {
    _policy.flush(_current, _commitPty);
  }

  void dispose() {
    _policy.cancel();
  }

  // ── Internals ───────────────────────────────────────────────────────────

  void _commitPty(int cols, int rows) {
    // Lock-step: resize the engine HERE (not in propose), atomically with the
    // PTY, so the grid changes once at stability instead of at every cell
    // boundary during a drag.
    _committedPty = TerminalGrid(cols, rows);
    _engine.resize(columns: cols, rows: rows);
    _ptyResizeCallback?.call(cols, rows);
  }

  void Function(int cols, int rows)? _ptyResizeCallback;

  /// Wire the PTY-side commit. Called once at setup by the session.
  void onPtyResize(void Function(int cols, int rows) callback) {
    _ptyResizeCallback = callback;
  }
}
```

**Design decisions:**

1. **Lock-step commit** — engine and PTY resize **together**, only when the policy commits (see §5bis.1). `propose()` measures + records the grid every frame but does not resize the engine (except the one-time init). During a drag the painter keeps the committed grid (blank space on the right, like orca's CSS-stretched canvas); at stability/settle/flush the engine + PTY adopt the new grid atomically. *(An earlier revision used a two-level commit — display immediate, PTY gated — but per-frame `engine.resize` reflowed the grid at every cell boundary and felt janky; reverted to lock-step.)*

2. **Transaction API** — `beginTransaction()` / `endTransaction(flush:)` bracket structural layout changes. The app-level coordinator (2.4) calls these.

3. **No callback from view to session** — the current `onViewportResize` callback chain (`terminal_view → terminal_session.onViewportResize → _syncPtyGeometryNow + _scheduleLayoutPtyGeometrySettle → transport.resize`) is replaced by a direct `controller → transport.resize` connection. `terminal_session` no longer participates in the resize decision.

### 2.4 Layer 4 — TerminalLayoutCoordinator (app-level)

Replaces `WorkspaceTerminalRegistry`'s resize coordination duties. One instance, provided via DI.

```dart
/// Coordinates resize across all TerminalResizeControllers during structural
/// layout changes (sidebar collapse, divider drag, worktree switch, tab open).
///
/// Counterpart of orca's holdPtyResizesForPaneSubtrees + SYNC_FIT_PANES_EVENT.
class TerminalLayoutCoordinator {
  final Set<TerminalResizeController> _controllers = {};

  void register(TerminalResizeController controller) {
    _controllers.add(controller);
  }

  void unregister(TerminalResizeController controller) {
    _controllers.remove(controller);
  }

  /// Run [action] while PTY resizes are held for all registered controllers.
  /// After [action] completes (synchronously or asynchronously), flush the
  /// final grid to the PTY. Use for:
  ///
  ///   - Sidebar open/close/collapse
  ///   - Split divider drag (beginDrag/endDrag)
  ///   - Worktree switch
  ///   - Tab open/close animation
  ///   - Font zoom change
  ///
  /// If [flush] is false, discard queued resizes (cancelled layout change).
  Future<void> runLayoutTransaction(
    Future<void> Function() action, {
    bool flush = true,
  }) async {
    for (final c in _controllers) {
      c.beginTransaction();
    }
    try {
      await action();
    } finally {
      for (final c in _controllers) {
        c.endTransaction(flush: flush);
      }
    }
  }

  /// Synchronous variant for purely synchronous layout changes.
  void runLayoutTransactionSync(
    void Function() action, {
    bool flush = true,
  }) {
    for (final c in _controllers) {
      c.beginTransaction();
    }
    try {
      action();
    } finally {
      for (final c in _controllers) {
        c.endTransaction(flush: flush);
      }
    }
  }

  /// Immediate flush for all controllers — used after a synchronous layout
  /// change that should take effect right now (similar to orca's
  /// SYNC_FIT_PANES_EVENT path for layout-effect pre-paint fit).
  void flushAllImmediate() {
    for (final c in _controllers) {
      c.commitNow();
    }
  }

  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers.clear();
  }
}
```

**Usage examples:**

```dart
// Sidebar toggle — hold PTY resizes during the transition, flush final size.
void _onToggleSidebar() {
  coordinator.runLayoutTransactionSync(() {
    setState(() => _sidebarOpen = !_sidebarOpen);
  });
}

// Divider drag — begin on drag start, end on drag end.
void _onDividerDragStart() {
  for (final c in _affectedControllers) c.beginTransaction();
}
void _onDividerDragEnd() {
  for (final c in _affectedControllers) c.endTransaction(flush: true);
}
```

---

## 3. Integration: what changes in each module

### 3.1 `flutter_alacritty/lib/ui/terminal_view.dart`

**Deleted:**
- `_cols`, `_rows` (grid tracking) → moved to `TerminalResizeController._current`
- `_pendingResizeCols`, `_pendingResizeRows`, `_resizeWindow` (90ms) → replaced by policy
- `_resizeThrottle` Timer → deleted
- `_ensureSizing` → replaced by controller.propose
- `_syncViewportToHost` → replaced by controller.propose
- `_applyViewportResize` → replaced by controller.propose
- `onViewportResize` callback → replaced by controller.onPtyResize
- `clamp(kMinTerminalColumns, 1000)` / `clamp(kMinTerminalRows, 1000)` → replaced by `ViewportGeometryResolver.resolve()` returning null

**Added:**
- `TerminalResizeController controller` parameter (required, or constructed internally with defaults)
- `TerminalLayoutCoordinator? coordinator` parameter (optional, auto-registers)

**Changed:**
- `LayoutBuilder` builder: calls `controller.propose(ViewportQuery(...))` instead of manual floor/clamp → `_ensureSizing`.
- `padding` → subtracted from constraints before passing to `ViewportQuery.available`, plus `reserve` for scrollbar gutter.
- `initState`: `engine.setCellPixels` still called, but grid init deferred to first `controller.propose`.

### 3.2 `flutter_alacritty/lib/engine/terminal_engine.dart`

No changes. `engine.resize` and same-size coalescing already work correctly.

### 3.3 `client/lib/services/terminal/terminal_session.dart`

**Deleted:**
- `onViewportResize(int columns, int rows)` → replaced by `_controller.onPtyResize`.
- `_hasPendingLayoutGeometry`, `_pendingViewportCols`, `_pendingViewportRows` → moved to controller.
- `_lastSyncedCols`, `_lastSyncedRows` → PTY-side dedup moves to `ResizeCommitPolicy` or transport layer.
- `_syncPtyGeometryNow` → replaced by `_commitPty` inside controller.
- `_scheduleLayoutPtyGeometrySettle` (80ms) → deleted.
- `_schedulePtyGeometry` (output-driven 80ms) → deleted. Output-driven re-sync was a workaround for the startup race; the controller solves this by initializing the engine at the first-proposal size before any PTY output arrives.
- `_applyOutputPtyGeometry` → deleted.
- `_ptyGeometryTimer`, `_ptyGeometrySettleTimer` → deleted.
- `_outputGeometryDebounceMs`, `_layoutGeometrySettleMs` → deleted.

**Added:**
- `TerminalResizeController? _resizeController` — set by host after construction.
- `void attachResizeController(TerminalResizeController controller)` — wires `controller.onPtyResize` to `_transport!.resize(rows, cols)`.

**Changed:**
- `connect` / `connectShell`: `cols`/`rows` captured at spawn time are now always fresh (controller already initialized by the time the async body runs).
- `_startTransport`: the deferred `engine.resize + initializeEmpty` path simplified — controller owns authoritative size.
- PTY resize is a simple `transport.resize(rows, cols)` sink — pure mechanism, zero policy.

### 3.4 `client/lib/widgets/workspace_terminal_panel.dart`

**Changed:**
- Creates and passes `TerminalResizeController` to `TerminalView`.
- Registers controller with `TerminalLayoutCoordinator` on mount.
- `ResizableSplitView.onDragStart` / `onDragEnd` call `coordinator.runLayoutTransactionSync` (or directly `controller.beginTransaction`/`endTransaction`).
- On workspace switch / worktree change: `coordinator.runLayoutTransaction(...)`.
- Scrollbar: add `reserve: EdgeInsets.only(right: 7)` to ViewportQuery (matching orca's scrollbar gutter).

### 3.5 `client/lib/pages/chat/chat_workbench_terminal.dart`

Same pattern as workspace panel: creates controller, passes to TerminalView.

### 3.6 `client/lib/services/terminal/workspace_terminal_registry.dart`

Can stay as-is for session lifecycle; resize coordination duties move to `TerminalLayoutCoordinator`.

### 3.7 New files (actual layout)

```
client/packages/flutter_alacritty/lib/ui/
  viewport_geometry.dart                # TerminalGrid, ViewportQuery, ViewportGeometryResolver
  resize_commit_policy.dart             # ResizeCommitPolicy, StableFrameCommitPolicy, ImmediateCommitPolicy
  terminal_resize_controller.dart       # TerminalResizeController (per-view orchestration)

client/packages/flutter_alacritty/test/
  viewport_geometry_test.dart           # 10 tests
  resize_commit_policy_test.dart        # 11 tests
  terminal_resize_controller_test.dart  # 13 tests

client/lib/services/terminal/
  terminal_layout_coordinator.dart      # TerminalLayoutCoordinator (app-level)

client/test/services/terminal/
  terminal_layout_coordinator_test.dart # 7 tests
```

**Rationale:** Controller, policy, and resolver live in `flutter_alacritty` because they are tightly coupled to `TerminalView` — the view owns one controller, the controller wraps the engine. The coordinator lives in the app layer because it coordinates across views (workspace panel + chat workbench).

---

## 4. Data flow summary

```
┌─────────────────────────────────────────────────────────┐
│ LayoutBuilder (every frame)                              │
│   avail = constraints.maxWidth/Height - padding          │
│   query = ViewportQuery(avail, cell, reserve)            │
│   grid = ViewportGeometryResolver.resolve(query)         │  ← pure, no side effects
│   controller.propose(query)                              │
│     ├─ engine init only on first proposal (lock-step)    │  ← NO per-frame resize
│     │                                                     │
│     └─ if in transaction: queue grid                     │
│        else if grid != null:                             │
│          policy.onProposal(grid, committed)               │  ← gated by stability
│            → (post-frame) policy.onFrame(commit)          │
│              → commit: engine.resize + transport.resize   │  ← atomic, PTY SIGWINCH
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Layout transaction (sidebar, divider, worktree, tab)     │
│                                                          │
│ coordinator.runLayoutTransaction(() {                    │
│   // structural DOM / widget tree change                 │
│   setState(...)                                          │
│ })                                                       │
│   ├─ beginTransaction() on all controllers               │
│   │   (proposals are queued, not sent to PTY)            │
│   ├─ action() — layout frames fire, grid proposals       │
│   │   change and are queued. Engine is NOT resized       │
│   │   (lock-step); painter keeps the committed grid.     │
│   └─ endTransaction(flush: true)                         │
│       → policy.flush(finalGrid, commit)                  │
│         → transport.resize → ONE SIGWINCH                │
└─────────────────────────────────────────────────────────┘
```

---

## 5. Startup sequence (the race that made output-driven re-sync necessary)

Current startup race:
1. `connect()` calls `_spawnTransport(cols: viewWidth, rows: viewHeight)` — at this point `viewWidth`/`viewHeight` are the DEFAULT 80×24 because the view hasn't mounted yet.
2. Timer(0) yields to event loop.
3. View mounts, LayoutBuilder fires, `onViewportResize` called with real grid.
4. Timer body resumes — engine is built at the real grid size (override from `_hasPendingLayoutGeometry`).
5. PTY output arrives → `_feedPtyBytes` → `_schedulePtyGeometry` → 80ms debounce → re-sync → this was the workaround for the case where the engine was built at 80×24 and the view's resize came too late.

New startup sequence:
1. `TerminalResizeController` is created and attached to the TerminalView before the session's `connect()`.
2. View mounts → LayoutBuilder → `controller.propose()` → engine is built at REAL size, `_initialized = true`.
3. `connect()` spawns transport — reads `controller.current` (already the real grid from step 2).
4. No race, no output-driven re-sync needed.

---

## 5bis. Deliberate deviations from orca

This architecture follows orca's pipeline closely, but makes several intentional departures:

### 5bis.1 Lock-step commit (display + PTY together, matching orca)

**Orca:** `fitAddon.fit()` synchronously resizes xterm (display + PTY together). During a drag, the canvas stretches via CSS but the grid (and PTY) only change when `safeFit()` fires — typically at stability, not every cell boundary.

**This spec (revised):** Engine resize moved from `propose()` (every LayoutBuilder frame) to `_commitPty()` (only when policy commits). During continuous resize, the display shows the committed grid (with empty space on the right that matches the viewport background), identical to orca's CSS-stretched canvas. When the policy commits (2-frame stability or settle or drag-end flush), both engine and PTY resize atomically. This eliminates the per-cell-boundary reflow that caused visible jank during drags — the grid now changes once per drag, not once per cell boundary.

**Initial revision used two-level commit** (display immediate, PTY deferred). This was revised after user testing showed that the per-frame `engine.resize()` calls during drags — even with same-size coalescing — caused the grid to change at every cell boundary, producing multiple reflows per drag. The revised approach matches orca exactly: engine + PTY resize together, only at stability.

### 5bis.2 Stability gate: aligned with orca's 2

**Orca:** 2 adjacent rAF frames with identical `proposeDimensions()` → `safeFit()`.

**This spec (as implemented):** 2 consecutive frames with identical proposals → commit (`maxStabilityFrames = 2`).

**History:** An earlier revision used 5 frames to over-filter layout noise, but Flutter's single layout pass per frame makes 2 sufficient (matching orca), and the higher threshold added latency. The total-frame safety valve (`safetyValveFrames = 8`) and the 150 ms settle timer cover the cases the stability gate alone cannot (continuous jitter, discrete one-shot resizes).

### 5bis.3 Settle timer (150ms wall-clock fallback)

**Orca:** Container-level `ResizeObserver` with 150ms debounce for continuous window resize; per-pane `pane-fit-resize-observer` with rAF stability for pane-level changes.

**This spec:** Single `StableFrameCommitPolicy` with frame-count stability gate + 150ms settle timer fallback. The initial design goal of "zero wall-clock timers" was revised after implementation testing showed discrete resizes (sidebar toggle, maximize) produce only 1–2 frames, making pure stability gating insufficient. The settle timer is cancelled on every new proposal — it only fires when the frame cycle goes silent, making it equivalent to orca's debounce.

### 5bis.4 Frame-driven policy (onProposal + onFrame split)

**Orca:** `requestAnimationFrame` callback reads `proposeDimensions()` at the start of each callback; the callback is the frame boundary.

**This spec:** `onProposal()` is called during layout (synchronous, inside `LayoutBuilder`); `onFrame()` is called from `SchedulerBinding.addPostFrameCallback`. This split matches Flutter's layout-then-draw frame cycle and allows the policy to be a pure state machine with no scheduler dependency.

---

## 6. What is deleted (inventory)

> **Status note (2026-06-22):** This is the *planned* deletion inventory. The
> new controller path is live, but the **legacy path is intentionally retained**
> as a fallback for callers that pass no `resizeController` (it becomes a no-op
> the moment a controller is attached). So the rows below describe the target
> end-state, not the current tree. Notably still present: `terminal_view.dart`
> `_cols/_rows` (used only by the legacy `_ensureSizing`; the controller path
> hit-tests the committed engine grid instead), `onViewportResize`, and
> `terminal_session.dart` `_scheduleLayoutPtyGeometrySettle` (80 ms). Remove
> these once all callers are migrated.

| Current code | Lines (approx) | Replacement |
|---|---|---|
| `terminal_view.dart` `_cols`, `_rows`, `_pendingResizeCols/Rows`, `_resizeWindow`, `_resizeThrottle`, `_ensureSizing`, `_syncViewportToHost`, `_applyViewportResize` (legacy path only) | ~60 | `controller.propose(query)` (~3 lines in LayoutBuilder) |
| `terminal_view.dart` `onViewportResize` callback field | ~5 | Delete; controller owns the PTY commit |
| `terminal_session.dart` `onViewportResize()` | ~15 | `controller._commitPty` (~3 lines) |
| `terminal_session.dart` `_hasPendingLayoutGeometry`, `_pendingViewportCols/Rows`, `_lastSyncedCols/Rows` | ~10 | `controller._current`, transport dedup |
| `terminal_session.dart` `_schedulePtyGeometry()` | ~20 | Deleted (no output-driven re-sync) |
| `terminal_session.dart` `_scheduleLayoutPtyGeometrySettle()` | ~20 | Deleted (no 80ms settle) |
| `terminal_session.dart` `_applyOutputPtyGeometry()` | ~12 | Deleted |
| `terminal_session.dart` `_syncPtyGeometryNow()` | ~12 | Merged into `_commitPty` |
| `terminal_session.dart` `_outputGeometryDebounceMs`, `_layoutGeometrySettleMs` | ~2 | Deleted |
| `terminal_session.dart` `_startTransport` startup-race overrides | ~10 | Simplified (controller is authoritative) |
| `workspace_terminal_panel.dart` `onViewportResize: entry.session.onViewportResize` | ~1 | `controller: _controller` |
| `chat_workbench_terminal.dart` same | ~1 | Same |

**Net:** ~170 lines deleted, ~250 lines added (new controller + resolver + policy + coordinator + tests), but the added lines are in clean, testable modules. The deleted lines are entangled timer chains.

---

## 7. Testing strategy

### 7.1 Unit tests (pure, no Flutter framework)

- `ViewportGeometryResolver`:
  - Normal viewport → correct grid
  - Too-small viewport → null
  - Edge case: exactly at minCols/minRows → returns grid
  - Edge case: 1px below min → null
  - `reserve` subtraction (scrollbar gutter)
- `StableFrameCommitPolicy`:
  - 5 identical proposals → commit on 5th
  - Changing proposals → no commit, counter resets
  - Safety valve after 15 frames of continuous change
  - `flush()` → immediate commit
  - `cancel()` → reset
- `TerminalResizeController`:
  - `propose(null)` → keeps current, no PTY commit
  - `propose(grid)` → engine resize, policy driven
  - `beginTransaction` / `endTransaction` → queued, flushed
  - Nested transactions → only outermost flush
  - `commitNow` → immediate

### 7.2 Widget tests

- `TerminalView` with controller: LayoutBuilder fires, controller.propose is called with correct ViewportQuery
- Padding/reserve subtraction
- View resize → controller gets new proposal each frame
- Font zoom → cell metrics change → new grid

### 7.3 Integration tests

- `TerminalLayoutCoordinator` with two controllers:
  - `runLayoutTransaction` holds for both, flushes for both
  - One controller disposed → removed from coordinator

### 7.4 Manual verification (golden path)

- Continuous window resize → terminal display tracks, TUI doesn't thrash
- Sidebar open/close → no flash, no TUI resize-jump
- Worktree switch → PTY receives at most one resize
- Divider drag → smooth, TUI only resizes at end
- Tab open/close → no intermediate grid reaches PTY
- Font zoom → resize applies, no flicker
- SSH session → resize works same as local

---

## 8. Open questions

1. **Scrollbar gutter in reserve.** Orca reserves 7px for the scrollbar as a gutter (so the scrollbar never covers content). TeamPilot currently doesn't have an always-visible scrollbar; the `reserve` should be 0 until a scrollbar is added. But adding `reserve` to the API now costs nothing and makes it trivial to add later.

2. **`maxStabilityFrames` tuning.** 5 is conservative; orca uses 8. The exact number should be tuned via real-app feel. The policy is a strategy — easy to swap.

3. **Should the controller live in `flutter_alacritty` or in the app layer?** The controller is view-level (one per TerminalView), so it belongs in `flutter_alacritty`. But the `TerminalLayoutCoordinator` is app-level (coordinates across views), so it belongs in the app layer. `ResizeCommitPolicy` and `ViewportGeometryResolver` are pure leaf modules — they can live anywhere. Recommendation: all four in `flutter_alacritty/lib/ui/` (the controller is tightly coupled to TerminalView), with the coordinator exposed for app-level wiring.

4. **Mobile.** The `StableFrameCommitPolicy` should work on mobile as-is because `SchedulerBinding.addPostFrameCallback` fires on every platform. If mobile needs different gating (e.g., keyboard appearance changes), swap the policy at the controller level.

5. **`kMinTerminalColumns=2` / `kMinTerminalRows=1` in the engine.** These stay as the VT-model floor (fullwidth glyph safety). They should never be exposed to the resize pipeline. The `ViewportGeometryResolver`'s `minCols=8, minRows=4` is the UI floor and is a separate constant.

---

## 9. Implementation order

1. **Create the four new modules with full unit tests** (pure logic, no widgets):
   - `ViewportGeometryResolver` + `TerminalGrid` + `ViewportQuery`
   - `ResizeCommitPolicy` + `StableFrameCommitPolicy` + `ImmediateCommitPolicy`
   - `TerminalResizeController`
   - `TerminalLayoutCoordinator`

2. **Integrate into `terminal_view.dart`:**
   - Add `TerminalResizeController` parameter
   - Replace LayoutBuilder body with `controller.propose(ViewportQuery(...))`
   - Delete old resize state variables and methods
   - Run existing `flutter_alacritty` tests → all green

3. **Simplify `terminal_session.dart`:**
   - Delete timer-based resize methods
   - Add `attachResizeController`
   - Wire `_commitPty` → `transport.resize(rows, cols)`
   - Simplify `_startTransport` startup sequence
   - Run terminal session tests → all green

4. **Wire the app layer:**
   - `WorkspaceTerminalPanel` creates controller, passes to TerminalView, registers with coordinator
   - `ChatWorkbenchTerminal` same
   - `ResizableSplitView` drag start/end → coordinator transaction
   - Worktree switch / sidebar toggle → coordinator transaction

5. **Manual verification** (full golden path per §7.4)

6. **Delete dead code:**
   - `onViewportResize` callback from `TerminalView`
   - All `_schedule*` / `_sync*` / `_apply*` methods in `terminal_session`

---

## 10. References

- orca `pane-fit-resize-observer.ts` — stability-frame gating via rAF
- orca `pane-tree-ops.ts` — `canMeasurePaneForFit`, `safeFit`, proposal==current skip
- orca `pane-pty-resize-hold.ts` — layout-transaction hold/flush
- orca `use-terminal-container-fit-sync.ts` — synchronous pre-paint fit + 150ms debounce
- alacritty `display/mod.rs` — cell grid changes → `term.resize()` at the Rust level
- TeamPilot `terminal_view.dart` — current resize: 90ms throttle, post-frame deferral, floor+clamp
- TeamPilot `terminal_session.dart` — current PTY: 80ms settle, output-driven 80ms re-sync
- [[worktree-sidebar-grouping]] — sidebar structure changes will exercise this pipeline heavily
- [[perf-debug-isolate-before-fixing]] — lesson: read orca, use layout-aligned gating, not wall-clock timers
