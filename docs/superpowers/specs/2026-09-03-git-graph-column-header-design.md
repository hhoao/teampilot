# Git Graph column header + short hash + hideable header

**Date:** 2026-09-03  
**Status:** Approved (conversation)  
**Related:** [2026-08-25-git-graph-design.md](./2026-08-25-git-graph-design.md)

## Goal

Align the commit graph list with VS Code Git Graph–style columns, add a column header row, show a short commit hash on each row, and let users hide/show the header (persisted).

## Layout

```
工具条 … [列头显隐按钮]
────────────────────────────────────────────
Graph │ Description │ Date │ Author │ Commit   ← hideable
────────────────────────────────────────────
 ●    │ main  fix…  │ 09/03 │ hhoao  │ 887647b4
```

### Columns (header and data rows share the same order and flex/width rules)

| Column | Content |
|--------|---------|
| Graph | Lane painter / node (existing) |
| Description | Branch/tag chips + subject (existing) |
| Date | Author date (`MM/dd HH:mm`) — **moved before Author** |
| Author | Author name |
| Commit | First 8 chars of hash; monospace; tap copies full hash (reuse existing copy-hash path / snackbar) |

Uncommitted row and spacer rows: no fake Date/Author/Commit values required; Description cell carries the uncommitted label + count badge; other meta cells empty or `—` only if needed for alignment (prefer empty).

### Alignment

Extract shared column metrics (graph width from lane count or a fixed min for the header; flex factors for Description / Date / Author / Commit) into a small helper used by both `GitGraphColumnHeader` and `GitGraphRowTile` so header labels sit above the matching data cells.

## Hide / show

| Entry | Behavior |
|-------|----------|
| Toolbar icon button | Toggle header visibility; tooltip switches with state |
| Header secondary-click → “Hide column header” | Hides header |
| When hidden | Only the toolbar button can show the header again |

- **Default:** header visible (`true`)
- **Persistence:** `LayoutPreferences.gitGraphHeaderVisible` (bool, default `true`), read/write via existing `LayoutCubit` / `LayoutRepository` path (same pattern as other layout toggles)

## UI pieces

- `GitGraphColumnHeader` — labels + bottom border; context menu for hide
- `GitGraphToolbar` — add compact icon toggle bound to layout preference
- `GitGraphRowTile` — reorder Date before Author; add Commit cell
- `_UncommittedTile` — keep Description-first content; leave trailing columns empty for alignment under the same column scaffold when header is shown
- Pane body: `Column(header?, Expanded(list))` so the header does not scroll away with the list

## l10n

Add (en + zh) keys for:

- Column titles: Graph, Description, Date, Author, Commit
- Toolbar tooltips: Show column header / Hide column header
- Context menu: Hide column header

## Out of scope

- Resizable columns
- Reorderable columns
- Hiding individual columns
- Changing detail-pane hash display

## Testing

1. Row tile: Date before Author; short hash visible; narrow width no overflow.
2. Header: renders five labels; secondary-click hides when wired with a fake/toggle callback.
3. Layout preference: `gitGraphHeaderVisible` round-trips in `LayoutPreferences` JSON (default true when absent).
4. Pane/toolbar: toggle updates visibility; hidden state shows no header widget.

## Files (expected)

- `client/lib/models/layout_preferences.dart` (+ cubit/tests if required by existing patterns)
- `client/lib/pages/git_graph/git_graph_column_header.dart` (new)
- `client/lib/pages/git_graph/git_graph_columns.dart` (shared metrics, optional but preferred)
- `client/lib/pages/git_graph/git_graph_row_tile.dart`
- `client/lib/pages/git_graph/git_graph_pane.dart`
- `client/lib/pages/git_graph/git_graph_toolbar.dart`
- `client/lib/l10n/app_en.arb`, `app_zh.arb`
- Tests under `client/test/pages/git_graph/` and layout preferences tests if present
