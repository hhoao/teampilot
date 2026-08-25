# Markdown preview search: rendered-text find with highlight & navigation in tp_markdown

## Problem

The markdown file preview (`_MarkdownPreviewPane` in `client/lib/pages/workbench/file_editor_surface.dart`) has **no search**. Source mode has full find/replace (re-editor `CodeFindController` + `CodeEditorFindPanel`), but switching to Preview loses all search affordance — for long documents the preview is where users read, and they cannot locate content.

Related gaps:

1. **tp_markdown has no search or highlight capability.** The IR (`MarkdownDocument` → blocks → inline runs) carries no text projection; `VirtualMarkdownView` (flatten mode, block-virtualized) exposes no way to highlight matches or scroll to a block.
2. **Chat transcript find** (`chat_transcript_find_controller.dart`) scans source text and navigates to *messages*, but never highlights matched substrings inside rendered markdown.
3. **re-editor's find is unusable for preview**: `CodeFindController` is bound to the line-text model and returns line/column selections — incompatible with a widget stream of rendered blocks.

## Decision

Build **rendered-text search inside tp_markdown** as a generic capability, and wire it into the file preview this phase:

- **Search semantics = what the user sees.** Matching runs over each container's concatenated plain text (post-markdown-parsing), so a query like `Hello World` matches across bold/emphasis/link run boundaries in source.
- **Highlight + navigate**: all matches painted with a highlight style, active match stronger; `n/N` counter with next/previous navigation that scrolls the match into view.
- **Match options**: case-sensitivity toggle + regex toggle (aligned with the editor find bar). Whole-word deferred.
- **Matches are confined to one text container** (a paragraph/heading/list-item/table-cell run sequence, or a code block's text). Cross-block matching creates ambiguous rendering and no user value; containers are the smallest complete render unit.
- **Hits are addressed by top-level block index + container path**, keeping search a document-level concept; the view maps blocks to its virtualization units itself (paragraph merging stays a view concern).
- **Explicit parameter threading, not InheritedWidget**: highlight context is deterministic per-build input passed down builder signatures (no compat constraints on the vendored package).
- **Reveal via controller** (`MarkdownViewController.revealBlock`), Flutter-idiomatic, reusable later by chat.

Out of scope this phase: replace (preview is read-only), whole-word toggle, chat-message integration (the package API is generic so chat can adopt it later).

## Architecture

Three layers: ① document-level search index → ② highlight injection at span-build time → ③ view-level reveal.

```
┌─ Client (file_editor_surface.dart preview pane) ────────────────────┐
│ MarkdownPreviewFindController   (state: query/hits/activeIndex)     │
│ MarkdownPreviewFindBar          (UI, reuses widgets/find primitives)│
│      │ query + highlight context            ↑ reveal                │
├─ tp_markdown ───────────────────────────────────────────────────────┤
│ ① MarkdownSearchIndex        (project IR → leaf text containers)    │
│ ② MarkdownHighlightContext   (span-split + style at build time)     │
│ ③ VirtualMarkdownView + MarkdownViewController (block→unit reveal)  │
└─────────────────────────────────────────────────────────────────────┘
```

### 1. Search index (`src/search/markdown_search_index.dart`)

A single O(n) walk projects the IR tree into an ordered list of **leaf text containers**:

```dart
class MarkdownSearchQuery {
  final String pattern;
  final bool caseSensitive;
  final bool regex; // invalid pattern -> MarkdownSearchException
}

class MarkdownSearchHit {
  final int container; // ordinal in document order
  final int start, end; // range within container plain text
}

class MarkdownSearchIndex {
  factory of(MarkdownDocument doc);          // cacheable alongside the document
  List<MarkdownSearchContainer> containers;  // plainText + address info
  List<MarkdownSearchHit> search(MarkdownSearchQuery q); // ordered, non-overlapping
}
```

Each container records:

- its **plain text** — runs flattened via the same traversal as `plainTextFromRuns` (TextRun/CodeRun text; Strong/Emphasis/Strike/Link children recursed; ImageRun alt text);
- an **offset ↔ run-path mapping** from plain-text offsets back into `(runIndex, offsetWithinRun)` so span building can split runs at match boundaries;
- its **address**: top-level `blockIndex` + structured path to the container (`self()` / `listItem(i)` / `child(j)` / `tableCell(row, col)` …).

`search()` compiles the query once (literal substring with case folding, or `RegExp`), scans every container's plain text, and returns hits ordered by container then offset. Overlapping regex matches collapse to the first (non-overlapping scan).

### 2. Highlight injection (`src/render/highlight_context.dart`)

```dart
/// Canonical route to a text container within a top-level block.
class MarkdownTextPath { /* sealed variants: self / listItem(i) / child(j) / tableCell(row,col) */ }

class MarkdownContainerHighlights {
  final List<TextRange> ranges; // all matches in this container
  final TextRange? active;      // current match (stronger style)
}

class MarkdownHighlightContext {
  MarkdownContainerHighlights? forContainer(int blockIndex, MarkdownTextPath path);
}
```

Rendering changes (signatures extended freely — vendored package):

- `markdown_tokens.dart`: new style pair `matchHighlight({required bool active})`; colors supplied by the app theme sheet.
- `inline_spans.dart`: `inlineSpans(..., highlights?)` walks the run tree tracking plain-text offsets, splits `TextRun`/`CodeRun` at range boundaries, wraps matched segments with the token styles. Paragraph/heading/merged-paragraph builders thread it through.
- `list_blockquote_blocks.dart` / `table_code_hr_blocks.dart`: as builders descend into nested containers (list items, task items, quote children, table cells, code-block text) they extend the path segment and query the context recursively.
- `block_widget_registry.dart` + both views: optional `highlights` parameter threaded into unit/block builds.

Only mounted units rebuild when the context changes; virtualization keeps per-frame cost bounded to visible blocks.

### 3. View reveal (`virtual_markdown_view.dart`)

- `_MarkdownUnit` records the range of top-level block indexes it covers → block→unit lookup.
- New `MarkdownViewController` bound by the view:

```dart
class MarkdownViewController {
  Future<void> revealBlock(int blockIndex); // scroll match's unit into view
}
```

- Target offset = height-cache `offsetBefore(unitIndex)` (+ intra-unit fraction later if needed).
  - **bounded mode**: drive the internal `ScrollController`.
  - **flatten mode**: the view already holds `_parentPosition`; target parent pixels = own `getOffsetToReveal` base + unit offset; `animateTo`.
- Far jumps land on estimated heights → post-frame second-pass correction (re-jump when delta > ~2 px) once real heights measure.

## Client integration (file preview)

| File | Role |
|------|------|
| `client/lib/services/editor/markdown_preview_find_controller.dart` | `ChangeNotifier`: query/options/hits/activeIndex; input debounce ~150 ms; on document identity change rebuilds index, keeps query, clamps activeIndex; `next()/previous()` wrap-around; invalid-regex error state; `close()` clears highlights |
| `client/lib/widgets/workbench/markdown_preview_find_bar.dart` | Find bar reusing `widgets/find/find_bar_widgets.dart` primitives (same visual language as editor find): case Aa / regex .* toggles, n/N counter, prev/next buttons, error hint |

`file_editor_surface.dart` changes:

- `_MarkdownPreviewPane` hoists the compiled `MarkdownDocument` into state so render and search share one instance.
- `ShortcutFocus` claims `Mod+F` to open the bar (mirrors the editor pane), `Esc` closes and clears; Enter/Shift+Enter = next/previous.
- The bar floats above preview content when open; toolbar gains a search icon button for discoverability.
- Pane passes `MarkdownHighlightContext` + `MarkdownViewController` into `VirtualMarkdownView`; find controller drives `revealBlock`.

Theme: `app_markdown_style_sheet.dart` fills the two match-highlight token styles from TpTheme colors.

l10n: reuse existing find-bar strings where present; add new keys only if missing (`app_en.arb` / `app_zh.arb`).

## Error handling & performance guards

| Scenario | Handling |
|----------|----------|
| Invalid regex | Catch format exception → error state shown in the bar; no highlights cleared |
| Too many hits | Cap at 10 000; counter shows `9999+`; beyond-cap hits excluded from navigation |
| Large documents | Index built O(n) once per document; input debounced |
| Document changed mid-search | Results carry a document generation tag; stale results discarded |
| Long-jump landing drift | Height estimates → post-frame second-pass correction (~2 px threshold) |
| Regex catastrophic backtracking | Dart RegExp has no timeout — accepted risk (same exposure as editor find) |
| Empty query | Clear highlights and counter |

## Testing

Package (`packages/tp_markdown/test/`):

- **Index projection**: container enumeration order incl. nesting (list items, quote children, table cells, code blocks); plain-text offset ↔ run-path mapping correctness.
- **Search**: literal case-sensitive/-insensitive; regex; invalid regex throws; cross-run-boundary match (e.g. `**Hel**lo` matching `Hello`); ordering; non-overlap.
- **Render**: pump tests inspecting the TextSpan tree — ranges split correctly across runs; active vs inactive styles distinct.
- **Reveal**: block→unit mapping incl. merged paragraph runs; `revealBlock` produces expected scroll target.

Client:

- Controller: debounce; wrap-around navigation; activeIndex clamped on new search; bad-regex error state.
- Widget test on the preview pane: `Mod+F` opens the bar; typing paints highlights; Enter navigates and triggers reveal; Esc closes and clears.

Conventions: constructor-injected fakes, no real IO; `flutter analyze --no-fatal-infos --no-fatal-warnings` clean; full non-integration suite green.

## Files

| File | Change |
|------|--------|
| `packages/tp_markdown/lib/src/search/markdown_search_index.dart` | new: query/hit/index/container projection |
| `packages/tp_markdown/lib/src/render/highlight_context.dart` | new: path types + context + container highlights |
| `packages/tp_markdown/lib/src/tokens/markdown_tokens.dart` | match-highlight style pair |
| `packages/tp_markdown/lib/src/render/inline_spans.dart` | span splitting + highlight styles; para/heading builders thread context |
| `packages/tp_markdown/lib/src/render/list_blockquote_blocks.dart` | nested-container path descent + highlight |
| `packages/tp_markdown/lib/src/render/table_code_hr_blocks.dart` | table cell / code text highlight |
| `packages/tp_markdown/lib/src/registry/block_widget_registry.dart` | thread optional highlights param |
| `packages/tp_markdown/lib/src/render/virtual_markdown_view.dart` | units record block ranges; `highlights` param; `MarkdownViewController` reveal (+ second-pass correction) |
| `packages/tp_markdown/lib/src/render/markdown_view.dart` | accept highlights (non-virtualized parity) |
| `packages/tp_markdown/lib/tp_markdown.dart` | export search + highlight + controller API |
| `client/lib/services/editor/markdown_preview_find_controller.dart` | new: find state owner |
| `client/lib/widgets/workbench/markdown_preview_find_bar.dart` | new: find bar UI |
| `client/lib/pages/workbench/file_editor_surface.dart` | pane hoists document; Mod+F/Esc wiring; hosts bar; passes context/controller |
| `client/lib/theme/app_markdown_style_sheet.dart` | match-highlight token colors |
| tests | package + client suites listed above |
