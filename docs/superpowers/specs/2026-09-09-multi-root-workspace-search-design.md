# Multi-Root Workspace Search — Design

Date: 2026-09-09
Status: Approved (pending spec review)

## Problem

Both search surfaces in a workspace are single-root today:

- The search dialog (`workspace_search_dialog.dart`) uses
  `workspace.firstFolderPath` for file-name search and content search.
- The right-tools content search panel (`right_tools_tool_views.dart`) uses
  `scope.roots.firstOrNull ?? widget.cwd` with a single filesystem.

A workspace with multiple project folders (multi-root, possibly mixed across
local / SSH / WSL / Termux targets) only searches the first folder; every other
folder is invisible to search.

## Goal

Search **all folders of the current workspace** from both surfaces, across all
targets, with per-slice concurrency, and group results **by directory**.
Session search is already workspace-scoped and unchanged. Cross-workspace
search is explicitly out of scope.

## New component: `MultiRootContentSearch`

`client/lib/services/search/multi_root_content_search.dart` — the fan-out and
aggregation layer over the existing `ContentSearchRunner`.

```dart
/// One search slice: a single root directory on one target.
class ContentSearchSlice {
  final Filesystem fs;    // target filesystem (local / SFTP / …)
  final String root;      // absolute path
  final String label;     // group-header display name
}

/// Stream event: a tagged match, or a per-slice failure.
class MultiRootSearchEvent {
  final ContentSearchSlice slice;
  final TpSearchMatch? match;   // non-null for match events
  final Object? error;          // non-null for slice-error events
}
```

Behavior:

- One `ContentSearchRunner` per slice (local/WSL → Rust engine, SFTP → Dart
  fallback — existing selection logic untouched), all slices run
  **concurrently**; events are merged and surfaced as they arrive.
- A slice that throws emits one slice-error event and is done; other slices
  keep streaming.
- `maxResults` is applied **per slice** (existing caps unchanged); the overall
  run is marked truncated when any slice hits its cap.
- `cancel()` cancels every in-flight runner (reusing each runner's cancel
  semantics, which also stop the Rust walker).

## Changes

### `ContentSearchCubit` (`cubits/content_search/content_search_cubit.dart`)

- `ContentSearchFileGroup` gains `rootKey` (the root path, unique group key)
  and `rootLabel`.
- The `runnerFactory` signature changes to receive the slice list; the cubit
  drives `MultiRootContentSearch` and aggregates by `(rootKey, path)`, with
  file groups emitted blocked per root (files of the same directory adjacent).
- State gains `sliceErrors: Map<String, Object>` keyed by `rootKey`: results
  render normally while failed directories show an error row.
- Replace flow: each file group builds its `ContentReplacer` with its own
  slice's filesystem (remote matches are replaced over the remote fs).

### Right-tools panel (`right_tools_tool_views.dart`, `search_panel.dart`)

- Parameters change from single `root` / `fs` to `List<ContentSearchSlice>`,
  built from `scope.targetSlices` (each slice's `tools.context.filesystem` +
  its roots). Fallback when no slice resolved: a single `cwd` slice, matching
  current behavior.
- Results render grouped by directory: a group header (directory label +
  backend tag), then file groups, then lines. Mixed backends show
  `rust / dart-fallback`.

### Search dialog (`workspace_search_dialog.dart`)

- File-name search iterates `workspace.folders`, querying
  `fileIndexFor(folder.path)` for each (indexes are already app-level cached in
  `WorkspaceSearchIndexes`), merging results grouped by directory. Per-folder
  caps follow the existing `_maxFileResults` / expanded values.
- `_warmIndexes` warms the file index for **every** folder root (currently only
  the first).
- The content section (`workspace_search_content_section.dart`) switches to
  `MultiRootContentSearch`, renders per-directory groups, and shows a per-slice
  error row on failure.
- `showWorkspaceSearchDialog` signature changes from a single `fs` to a slice
  list; `workspace_split_pane._openSearch` builds it from the tools scope.

### Opening results

`onOpenFile(path)` passes an absolute path to
`WorkbenchEditorOpener.openFile(workspaceId, path)` — unchanged. During
implementation, verify that a path under a non-first (or remote) root routes
to the correct target's editor; the first root being remote already works
through this path today.

## Data flow

```
query input
  → cubit / content section builds TpSearchOptions
  → MultiRootContentSearch: one ContentSearchRunner per slice, concurrent
  → merged stream of tagged matches (+ per-slice errors)
  → cubit aggregates by (rootKey, path), blocks file groups per root
  → UI: [directory header → file groups → lines] × N + error rows
```

Cancellation / new query: the existing `_searchSeq` sequence guard plus
per-slice `cancel()`; a new query cancels all in-flight walks.

## Edge cases

- **SSH target unreachable** — that slice fails fast; error row for its
  directory, other slices unaffected.
- **Multiple roots on one target** — each root is its own slice and group.
- **No slices resolved** (scope still resolving) — fall back to the `cwd`
  slice (current behavior preserved).
- **Result caps** — per slice (panel: existing cap logic; dialog: 500), the
  truncated flag set when any slice hits its cap.

## Testing

- `MultiRootContentSearch`: fake filesystems — concurrent merge, single-slice
  error isolation, cancellation, per-slice truncation.
- `ContentSearchCubit`: multi-root grouped aggregation, `sliceErrors` state,
  per-slice replace.
- Dialog file-name search: multi-folder merge, per-directory grouping, caps.
- Existing single-root tests migrate to the slice-list API and must stay
  behaviorally equivalent.

## l10n

New strings (en + zh arb only): per-directory error row ("此目录搜索失败"),
mixed backend label.
