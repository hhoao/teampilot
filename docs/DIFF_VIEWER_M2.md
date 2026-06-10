# Side-by-side Diff Viewer (M2)

> **Status: shipped.** This is the original design note, kept for context. The
> feature is implemented under `client/lib/services/diff/` and
> `client/lib/widgets/diff/` (entry: `DiffViewer` / `SideBySideDiffView`, wired
> from `widgets/git/git_diff_view.dart` + `git_source_control_panel.dart`). The
> task list at the bottom is historical.

IDEA-style two-pane diff: line alignment, inline char highlight, syntax color,
connecting ribbon. Replaces/augments the unified-text `GitDiffDialog`.

## Why this is feasible

re-editor renders background decorations through `_CodeFieldExtraRender`, a list
of painters (cursor line, selection, find-highlight). `_CodeFieldSelectionsPainter`
already turns a `List<CodeLineSelection>` into per-paragraph rects (line-spanning
and char-range). So **line backgrounds + inline char highlight need no new paint
logic** — only a painter that lets each range carry its own color, plus a prop on
`CodeEditor` to feed it. Minimal, upgrade-safe patch to the vendored package.

## Module layout

```
client/lib/
  services/diff/
    diff_model.dart            # DiffRow / InlineEdit / DiffBlock / DiffResult (pure)
    diff_options.dart          # ignoreWhitespace / ignoreCase
    diff_engine.dart           # Myers line diff + char diff + row alignment (pure)
    line_pairing.dart          # similarity pairing for replace blocks
    unified_diff_parser.dart   # git unified diff -> before/after
    diff_decoration_mapper.dart# DiffRow ranges -> re-editor diffDecorations
  widgets/diff/
    diff_viewer.dart           # entry widget: mode switch (side-by-side / unified)
    side_by_side_diff_view.dart# two read-only CodeEditors + scroll sync
    unified_diff_view.dart     # single-pane unified fallback
    diff_view_controller.dart  # shared diff state / navigation
    diff_ribbon_painter.dart   # connecting ribbon CustomPaint
    diff_overview_ruler.dart   # minimap-style change overview
    diff_toolbar.dart          # ignore-ws / next-prev / viewer switch
  packages/re-editor/          # controlled patch: diff painter + CodeEditor prop
```

## Data model (`diff_model.dart`)

`DiffRow` is the aligned render/scroll unit: `kind` (equal|insert|delete|modify),
nullable `leftLineNo`/`rightLineNo` (null = filler row on that side), text per
side, and `InlineEdit` ranges (char `[start,end)` + isAdd) for modify rows.
`DiffBlock` groups consecutive non-equal rows for ribbon + next/prev navigation.

## Engine (`diff_engine.dart`)

| Step | Algorithm |
|------|-----------|
| Line diff | Myers O(ND), self-implemented |
| Block pairing | replace block = adjacent delete-run + insert-run; pair by similarity (task 2 refines; task 1 = index order) |
| Inline diff | char-level Myers on paired lines -> InlineEdit ranges |
| Normalize | ignoreWhitespace/Case affect equality only; render uses original text |

Pure functions, zero Flutter deps -> isolate-friendly (`compute()` for big files).

## re-editor patch (3 spots)

1. `_CodeFieldDiffPainter extends _CodeFieldExtraPainter` reusing the selections
   rect logic but per-range color; add to `_backgroundRender.painters`.
2. `CodeEditor.diffDecorations` prop, transparently passed through (mirror the
   existing `highlightSelections` setter plumbing).
3. Gutter via existing `indicatorBuilder` (no package change).

## Widget layer

Left/right read-only `CodeEditor`s fed split text + `diffDecorations` +
`codeHighlightThemeFor(ext)` (reuse `services/editor/file_editor_theme.dart`).
Vertical scroll synced across the two `CodeScrollController`s (reentrancy guard);
horizontal independent; `wordWrap: false`. Center `CustomPaint` draws ribbons per
`DiffBlock`. Toolbar toggles ignore-whitespace (re-run engine), jumps changes,
switches viewer mode (keep `GitDiffDialog` as unified fallback).

## Integration

`SideBySideDiffView.show(...)` mirrors `GitDiffDialog.show`; source-control panel
switches to it. Source data: parse git's unified diff (task 3) rather than
re-diffing, to honor git's rename/context.

## Tasks (all completed)

1. ✅ model + line Myers + row alignment + tests
2. ✅ similarity pairing + inline char diff + tests
3. ✅ unified diff parser + tests
4. ✅ re-editor patch (painter + prop)
5. ✅ side-by-side view + scroll sync + gutter
6. ✅ ribbon painter
7. ✅ toolbar (ignore-ws / nav / switch) + l10n
8. ✅ wire source-control, fallback, polish

## Risks

Pairing accuracy (tunable threshold + tests); scroll-sync reentrancy (guard +
equal total rows via fillers); package upgrade conflicts (minimal patch, annotated);
large-file perf (engine in `compute()`, render reuses re-editor virtual scroll).
