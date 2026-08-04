# MultiPane resize content stability

## Problem

Dragging IDE sidebars (`MultiPane` + `PaneController`) is build-bound janky. Evidence from DevTools export `test23.json` (240 Hz, ~4.17 ms budget):

- 61/61 frames janky; worst ~147 ms total with ~91 ms **build**
- Per drag frame: ~49× `FileTreeNode` / `TpHover` / `DragTarget` rebuilds (right tools)
- `MultiPane` / `Resizer` rebuild on every size notify

**Root cause:** every `PaneController` size notify calls `MultiPane.setState`, which re-invokes `paneBuilder` for **all** panes. `TweenAnimationBuilder` already reuses its `child` across **animation** ticks; **resize** ticks still reconstruct that child because the parent rebuilds and creates a new widget subtree.

**Asymmetry:** left-edge drag changes left pixel width; right pane’s constraints stay the same, but the file tree still **builds**. Right-edge drag pays build **and** layout of the heavy tools pane — feels worse.

Prefs persistence is already correct: `WorkspaceIdeShell` commits widths on drag end only (`isResizing` gate). Out of scope for this change.

## Decision

Match industry splitter practice (VS Code `SplitView` / sash): **resize updates slot sizes only; pane content instances stay stable.**

In `packages/panes` `MultiPane`, keep a stable content widget per pane and **do not** call `paneBuilder` again when only pixel/fraction sizes change.

| Event | `paneBuilder` |
|-------|----------------|
| Pixel / fraction size change (incl. every resize delta) | **No** — reuse cached content |
| Show / hide (visibility end-state → `animationProgress` 0.0 or 1.0) | **Yes** once when the end-state changes — **not** on every tween tick |
| Maximize / unmaximize | **Yes** |
| Entries add / remove / reorder | **Yes** |
| `paneBuilder` identity change (`didUpdateWidget`) | **Yes** — clear cache |
| `controller` instance replaced (`didUpdateWidget`) | **Yes** — clear cache |

`animationProgress` today is only the visibility endpoint (0.0 / 1.0) passed into `paneBuilder`; size tweening stays inside `TweenAnimationBuilder` and must not re-invoke the builder per tick (existing test).

No new public API on `PaneController` or `WorkspaceIdeShell`. No drag-time clip / deferred reflow. No file-tree virtualization in this spec.

## Approach

Preferred implementation (internal to `MultiPane`):

- Introduce a small private host (e.g. `_StablePaneContent`) keyed by `paneId`, holding the last `paneBuilder` output.
- Invalidate when `animationProgress` (or equivalent visibility flag passed into the builder) changes, or when the `PaneBuilder` tear-off / callback identity changes.
- Pixel path: pass the stable widget as `TweenAnimationBuilder.child` (same as today).
- Fraction path: wrap `Expanded`’s child the same way.
- On controller notify that is size-only, `setState` still runs so slot `SizedBox` / flex updates; content Elements keep the same Widget instance and skip subtree rebuild.

Rejected alternatives:

- **Drag-time overflow/clip without reflow** — better right-edge feel, different UX; defer.
- **App-level `RepaintBoundary` / file-tree only** — does not stop `paneBuilder` fan-out; treat as follow-up if layout remains hot after this.
- **Granular `PaneController` listeners (size vs structure)** — nicer long-term, larger API surface; stable content host is enough for the measured rebuild storm.

## Acceptance

Automated (`client/packages/panes/test`):

1. After first layout, `beginResize` + several `resize` deltas + pumps: `paneBuilder` invoke count for each pane **unchanged** (cover both a pixel pane and a fraction pane).
2. Existing test: pixel pane builder not invoked on every **animation** tick — still passes.
3. Show/hide: builder runs when visibility end-state flips; not on intermediate size-tween pumps after that flip’s first build.
4. Maximize then restore (and/or entries change): builder runs again for affected panes (cache invalidated).

Manual / perf (optional regression check):

- Left sash drag with right tools open: right file-tree widgets should not show mass rebuilds in Rebuild Stats.
- Right sash drag: rebuild storm gone; remaining cost is layout of the resizing pane (expected heavier than left).

## Out of scope

- `LayoutCubit` width write path (already drag-end).
- File tree / `TpHover` cost reduction.
- Skipping layout of the pane whose width is actively changing.
- Nested `IdeLayout` center/bottom axis beyond the same `MultiPane` behavior (inherits automatically).
