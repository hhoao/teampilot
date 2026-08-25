# Markdown Preview Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add rendered-text find (highlight + n/N navigation, case/regex options) to the markdown file preview, built as a generic search/highlight capability inside the `tp_markdown` package.

**Architecture:** Three layers: ① a document-level `MarkdownSearchIndex` projecting the IR into ordered leaf text containers and searching their plain text; ② highlight injection at TextSpan-build time via an explicit `MarkdownHighlightContext` threaded through builders; ③ `VirtualMarkdownView` reveal via a `MarkdownViewController` driving internal or parent scroll. Client side: a debounced `ChangeNotifier` find controller + a VS Code-style find bar wired into the preview pane (`Mod+F`, `Esc`, Enter/Shift+Enter).

**Spec:** `docs/superpowers/specs/2026-08-25-markdown-preview-search-design.md`

**Tech Stack:** Flutter/Dart; vendored packages edited in place (`client/packages/tp_markdown`); re-editor only for its `CodeLineEditingController`; existing find-bar primitives in `client/lib/widgets/find/`.

## Global Constraints

- Verify with: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` then `cd client && dart run tool/run_tests.dart` (final task). Package-only iteration: `cd client/packages/tp_markdown && flutter test`.
- Flutter SDK patches are mandatory — environment assumed already provisioned per `docs/flutter-patches.md`. If tooling errors mention SDK mismatch, STOP and report.
- No new l10n keys required: reuse the `editorFind*` family already present in `client/lib/l10n/app_en.arb` / `app_zh.arb`.
- No changes to `client/lib/widgets/find/*` primitives (the find bar composes them as-is).
- Follow existing dartdoc comment style of each touched file; no `print`; no raw paths/UI IO.
- Commits: one per task, conventional prefixes (`feat(tp_markdown): …`, `feat(editor): …`, `refactor(editor): …`).
- Hit cap constant: `kMarkdownSearchMaxHits = 10000` (counter shows `<cap>+` beyond).
- Match semantics: search runs over **rendered plain text per container**; matches never cross container boundaries; image alt text excluded.

---

### Task 1: Highlight context types + match-highlight token styles

**Files:**
- Create: `client/packages/tp_markdown/lib/src/render/highlight_context.dart`
- Modify: `client/packages/tp_markdown/lib/src/tokens/markdown_tokens.dart`
- Test: `client/packages/tp_markdown/test/markdown_highlight_context_test.dart`

**Interfaces:**
- Consumes: nothing (leaf types).
- Produces (used by all later tasks):
  - `sealed class MarkdownPathStep` with `final class ListItemStep(int item)`, `ChildStep(int index)`, `TableHeaderStep(int col)`, `TableCellStep(int row, int col)` — value equality on fields.
  - `class MarkdownContainerHighlights { List<TextRange> ranges; TextRange? active; }`
  - `abstract interface class MarkdownHighlightContext { MarkdownContainerHighlights? forContainer(int blockIndex, List<MarkdownPathStep> path); }`
  - `MarkdownTokens.matchHighlightColor` / `.matchHighlightActiveColor` (non-null, defaulted) and `TextStyle matchHighlight(TextStyle base, {required bool active})`.

- [ ] **Step 1: Write the failing test**

```dart
// client/packages/tp_markdown/test/markdown_highlight_context_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/src/render/highlight_context.dart';
import 'package:tp_markdown/src/tokens/markdown_tokens.dart';

void main() {
  group('MarkdownPathStep equality', () {
    test('same fields equal, different not', () {
      expect(const ListItemStep(1), const ListItemStep(1));
      expect(const ListItemStep(1), isNot(const ListItemStep(2)));
      expect(const ChildStep(0), isNot(const ListItemStep(0)));
      expect(
        const TableCellStep(0, 1),
        const TableCellStep(0, 1),
      );
    });
  });

  group('MarkdownTokens.matchHighlight', () {
    final tokens = MarkdownTokens.test();
    test('keeps base glyph metrics, swaps background', () {
      final base = tokens.body;
      final inactive = tokens.matchHighlight(base, active: false);
      final active = tokens.matchHighlight(base, active: true);
      expect(inactive.backgroundColor, tokens.matchHighlightColor);
      expect(active.backgroundColor, tokens.matchHighlightActiveColor);
      expect(active.backgroundColor, isNot(inactive.backgroundColor));
      expect(inactive.fontSize, base.fontSize);
      expect(inactive.fontFamily, base.fontFamily);
    });
  });

  group('lookup context', () {
    test('returns registered ranges for exact path', () {
      final ctx = _MapContext({
        (
          3,
          const [ListItemStep(0)],
        ): const MarkdownContainerHighlights(ranges: [TextRange(start: 0, end: 4)]),
      });
      expect(
        ctx.forContainer(3, const [ListItemStep(0)])?.ranges,
        hasLength(1),
      );
      expect(ctx.forContainer(3, const [ListItemStep(1)]), isNull);
      expect(ctx.forContainer(4, const []), isNull);
    });
  });
}

class _MapContext implements MarkdownHighlightContext {
  _MapContext(this.entries);
  final Map<(int, List<MarkdownPathStep>), MarkdownContainerHighlights> entries;

  @override
  MarkdownContainerHighlights? forContainer(
    int blockIndex,
    List<MarkdownPathStep> path,
  ) =>
      entries[(blockIndex, path)];
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/tp_markdown && flutter test test/markdown_highlight_context_test.dart`
Expected: FAIL — `highlight_context.dart` not found / `matchHighlight` undefined.

- [ ] **Step 3: Implement**

Create `client/packages/tp_markdown/lib/src/render/highlight_context.dart`:

```dart
import 'package:flutter/material.dart';

/// One step on the route from a top-level block down to a nested text
/// container. A container address = top-level block index + ordered steps.
sealed class MarkdownPathStep {
  const MarkdownPathStep();
}

/// Into [ListBlock.items] at [item] (its own runs, or the prefix for children).
final class ListItemStep extends MarkdownPathStep {
  const ListItemStep(this.item);

  final int item;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ListItemStep && other.item == item;

  @override
  int get hashCode => Object.hash(ListItemStep, item);
}

/// Into nested child blocks (list-item children / blockquote children).
final class ChildStep extends MarkdownPathStep {
  const ChildStep(this.index);

  final int index;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ChildStep && other.index == index;

  @override
  int get hashCode => Object.hash(ChildStep, index);
}

/// Table header cell at column [col].
final class TableHeaderStep extends MarkdownPathStep {
  const TableHeaderStep(this.col);

  final int col;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TableHeaderStep && other.col == col;

  @override
  int get hashCode => Object.hash(TableHeaderStep, col);
}

/// Table body cell at [row] x [col].
final class TableCellStep extends MarkdownPathStep {
  const TableCellStep(this.row, this.col);

  final int row;
  final int col;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TableCellStep && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(TableCellStep, row, col);
}

/// Highlights for one text container: every match range plus the currently
/// navigated one (rendered stronger).
class MarkdownContainerHighlights {
  const MarkdownContainerHighlights({required this.ranges, this.active});

  /// All match ranges within the container's plain text.
  final List<TextRange> ranges;

  /// The active match (must be contained in one of [ranges]); `null` = none.
  final TextRange? active;
}

/// Resolves per-container highlight ranges during rendering. Views look up by
/// address and pass the result down into span building.
abstract interface class MarkdownHighlightContext {
  MarkdownContainerHighlights? forContainer(
    int blockIndex,
    List<MarkdownPathStep> path,
  );
}
```

Modify `markdown_tokens.dart`:

1. Constructor: add optional params after `strikeDecoration`:

```dart
    this.matchHighlightColor = const Color(0x2690CAF9),
    this.matchHighlightActiveColor = const Color(0x66FFB74D),
```

2. Fields (after `strikeDecoration`):

```dart
  /// Background wash painted over non-active search matches.
  final Color matchHighlightColor;

  /// Background wash painted over the active (navigated) search match.
  final Color matchHighlightActiveColor;
```

3. Method (after `inlineCodeAt`):

```dart
  /// Search-match paint over [base]: background wash only; [active] stronger.
  TextStyle matchHighlight(TextStyle base, {required bool active}) =>
      base.copyWith(
        backgroundColor:
            active ? matchHighlightActiveColor : matchHighlightColor,
      );
```

(`MarkdownTokens.test()` needs no change — defaults apply.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client/packages/tp_markdown && flutter test test/markdown_highlight_context_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/packages/tp_markdown/lib/src/render/highlight_context.dart \
  client/packages/tp_markdown/lib/src/tokens/markdown_tokens.dart \
  client/packages/tp_markdown/test/markdown_highlight_context_test.dart
git commit -m "feat(tp_markdown): highlight context types + match-highlight tokens"
```

---

### Task 2: Search index — containers, query, hits

**Files:**
- Create: `client/packages/tp_markdown/lib/src/search/markdown_search_index.dart`
- Test: `client/packages/tp_markdown/test/markdown_search_index_test.dart`

**Interfaces:**
- Consumes: `MarkdownDocument` IR (`src/ir/markdown_document.dart`), `MarkdownPathStep`/`MarkdownHighlightContext`/`MarkdownContainerHighlights` from Task 1, and `inlineTextPieces(List<InlineRun>)` from `src/render/inline_spans.dart`.

  NOTE: `inlineTextPieces` lands in Task 3 Step 3. To keep Task 2 self-contained, implement it NOW as part of Task 3's final home but create it in this task inside inline_spans.dart (additive-only change), so both tasks compile:

  Append to `client/packages/tp_markdown/lib/src/render/inline_spans.dart`:

```dart
/// One leaf text piece in document order ([TextRun]/[CodeRun] glyphs).
/// Images render as unsplittable [WidgetSpan]s and are excluded.
class InlineTextPiece {
  const InlineTextPiece(this.text);

  final String text;
}

/// Ordered leaf text pieces of [runs]; the canonical traversal shared by the
/// search-index projection and highlight-aware span splitting.
List<InlineTextPiece> inlineTextPieces(List<InlineRun> runs) {
  final pieces = <InlineTextPiece>[];
  void walk(List<InlineRun> list) {
    for (final run in list) {
      switch (run) {
        case TextRun(:final text):
          pieces.add(InlineTextPiece(text));
        case CodeRun(:final text):
          pieces.add(InlineTextPiece(text));
        case StrongRun(:final children) ||
              EmphasisRun(:final children) ||
              StrikeRun(:final children) ||
              LinkRun(:final children):
          walk(children);
        case ImageRun():
          break;
      }
    }
  }

  walk(runs);
  return pieces;
}
```

  Also rewrite existing `plainTextFromRuns` to delegate (behavior preserved except image alt now excluded — grep app usages first: `rg -n "plainTextFromRuns" client/lib client/packages` and verify callers tolerate alt exclusion; chat transcript indexing uses its own builder, expected no impact — if a caller depends on alt inclusion, leave that caller unchanged and note it in the commit message):

```dart
String plainTextFromRuns(List<InlineRun> runs) =>
    inlineTextPieces(runs).map((p) => p.text).join();
```

- Produces:
  - `const MarkdownSearchQuery({required String pattern, bool caseSensitive = false, bool regex = false})` (value equality).
  - `class MarkdownSearchHit { int container; int start; int end; }`
  - `class MarkdownSearchContainer { int blockIndex; List<MarkdownPathStep> path; String plainText; }`
  - `class MarkdownSearchIndex { factory of(MarkdownDocument); List<MarkdownSearchContainer> containers; List<MarkdownSearchHit> search(MarkdownSearchQuery); }`
  - `class MarkdownSearchException implements Exception { String message; }`
  - `const int kMarkdownSearchMaxHits = 10000;`
  - `class MarkdownSearchHighlightContext implements MarkdownHighlightContext { factory of(MarkdownSearchIndex, List<MarkdownSearchHit>, {int activeOrdinal}); }` plus convenience `index.highlightsFor(hits, {activeOrdinal})`.

- [ ] **Step 1: Write the failing test**

```dart
// client/packages/tp_markdown/test/markdown_search_index_test.dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/src/ir/markdown_document.dart';
import 'package:tp_markdown/src/render/highlight_context.dart';
import 'package:tp_markdown/src/search/markdown_search_index.dart';

void main() {
  MarkdownDocument doc() => const MarkdownDocument(blocks: [
        ParagraphBlock(runs: [
          TextRun('Hello '),
          StrongRun(children: [TextRun('World')]),
          TextRun(' again'),
        ]),
        HeadingBlock(level: 2, runs: [TextRun('World Title')]),
        CodeBlock(language: 'dart', text: 'final world = 1;\n'),
        BlockquoteBlock(blocks: [
          ParagraphBlock(runs: [TextRun('quoted world')]),
        ]),
        ListBlock(ordered: false, items: [
          ContentListItem(runs: [TextRun('item world one')]),
        ]),
        TableBlock(headers: [
          InlineDocument(runs: [TextRun('Col World')])
        ], rows: [
          [InlineDocument(runs: [TextRun('cell world')])]
        ]),
      ]);

  group('projection', () {
    final index = MarkdownSearchIndex.of(doc());
    test('enumerates containers in document order incl. nesting', () {
      final kinds = index.containers
          .map((c) => (c.blockIndex, c.path.map((s) => s.runtimeType).toList()))
          .toList();
      expect(kinds, [
        (0, <Type>[]),
        (1, <Type>[]),
        (2, <Type>[]),
        (3, [ChildStep]),
        (4, [ListItemStep]),
        (5, [TableHeaderStep]),
        (5, [TableCellStep]),
      ]);
    });

    test('plain text crosses run boundaries', () {
      expect(index.containers.first.plainText, 'Hello World again');
      expect(index.containers[2].plainText, 'final world = 1;\n');
    });
  });

  group('search', () {
    final index = MarkdownSearchIndex.of(doc());

    test('literal case-insensitive matches across bold boundary', () {
      final hits = index.search(const MarkdownSearchQuery(pattern: 'world'));
      // paragraph, heading, quote, list item, header cell, body cell
      expect(hits, hasLength(6));
      expect(hits.first.container, 0);
      expect((hits.first.start, hits.first.end), (6, 11));
    });

    test('case sensitive filters', () {
      final hits = index.search(
        const MarkdownSearchQuery(pattern: 'World', caseSensitive: true),
      );
      expect(hits, hasLength(2)); // paragraph bold + heading
    });

    test('regex works and skips zero-length matches', () {
      final hits = index
          .search(const MarkdownSearchQuery(pattern: r'w(orl)d', regex: true));
      expect(hits, hasLength(6));
      expect(hits.first.end - hits.first.start, 5);
      final empty = index
          .search(const MarkdownSearchQuery(pattern: r'x*', regex: true));
      expect(empty, isEmpty);
    });

    test('invalid regex throws MarkdownSearchException', () {
      expect(
        () => index.search(const MarkdownSearchQuery(pattern: '([', regex: true)),
        throwsA(isA<MarkdownSearchException>()),
      );
    });

    test('empty pattern yields no hits', () {
      expect(index.search(const MarkdownSearchQuery(pattern: '')), isEmpty);
    });

    test('highlight context marks active ordinal', () {
      final hits = index.search(const MarkdownSearchQuery(pattern: 'world'));
      final ctx = index.highlightsFor(hits, activeOrdinal: 1);
      final c = index.containers[hits[1].container];
      final hl =
          ctx.forContainer(c.blockIndex, c.path)!;
      expect(hl.active, TextRange(start: hits[1].start, end: hits[1].end));
      expect(ctx.forContainer(99, const []), isNull);
    });

    test('hit cap stops scanning', () {
      final repetitive = const MarkdownDocument(blocks: [
        ParagraphBlock(runs: [TextRun('a a a a a a a a a a')])
      ]);
      final idx = MarkdownSearchIndex.of(repetitive);
      final hits = idx.search(const MarkdownSearchQuery(pattern: 'a'));
      expect(hits.length <= kMarkdownSearchMaxHits, isTrue);
    });
  });
}
```

Note: if `(a, b)` record-equality syntax in expectations trips the analyzer version, replace with individual `expect(hits.first.start, 6)` style asserts.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/tp_markdown && flutter test test/markdown_search_index_test.dart`
Expected: FAIL — `markdown_search_index.dart` missing.

- [ ] **Step 3: Implement**

Create `client/packages/tp_markdown/lib/src/search/markdown_search_index.dart`:

```dart
import 'dart:ui' show TextRange;

import '../ir/markdown_document.dart';
import '../render/highlight_context.dart';
import '../render/inline_spans.dart';

/// Thrown when a regex query fails to compile.
class MarkdownSearchException implements Exception {
  const MarkdownSearchException(this.message);

  final String message;

  @override
  String toString() => 'MarkdownSearchException: $message';
}

/// Cap on returned hits; navigation stops counting beyond this.
const int kMarkdownSearchMaxHits = 10000;

/// Find parameters over rendered plain text.
class MarkdownSearchQuery {
  const MarkdownSearchQuery({
    required this.pattern,
    this.caseSensitive = false,
    this.regex = false,
  });

  final String pattern;
  final bool caseSensitive;
  final bool regex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownSearchQuery &&
          other.pattern == pattern &&
          other.caseSensitive == caseSensitive &&
          other.regex == regex;

  @override
  int get hashCode => Object.hash(pattern, caseSensitive, regex);
}

/// One match: container ordinal + range in its plain text.
class MarkdownSearchHit {
  const MarkdownSearchHit({
    required this.container,
    required this.start,
    required this.end,
  });

  final int container;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownSearchHit &&
          other.container == container &&
          other.start == start &&
          other.end == end;

  @override
  int get hashCode => Object.hash(container, start, end);
}

/// One searchable leaf text container (paragraph/heading/list-item/table-cell
/// run sequence, or code-block text), addressed by top-level block + path.
class MarkdownSearchContainer {
  const MarkdownSearchContainer({
    required this.blockIndex,
    required this.path,
    required this.plainText,
  });

  final int blockIndex;
  final List<MarkdownPathStep> path;
  final String plainText;
}

/// Document-level search: projects the IR into ordered containers once, scans
/// their plain text per query.
class MarkdownSearchIndex {
  factory MarkdownSearchIndex.of(MarkdownDocument document) {
    final containers = <MarkdownSearchContainer>[];
    void visitBlocks(
      List<MarkdownBlock> blocks,
      int blockIndex,
      List<MarkdownPathStep> basePath,
    ) {
      for (var i = 0; i < blocks.length; i++) {
        visitBlock(blocks[i], blockIndex, basePath);
      }
    }

    void addRuns(
      List<InlineRun> runs,
      int blockIndex,
      List<MarkdownPathStep> path,
    ) {
      final text =
          inlineTextPieces(runs).map((p) => p.text).join();
      if (text.isEmpty) return;
      containers.add(
        MarkdownSearchContainer(
          blockIndex: blockIndex,
          path: List.unmodifiable(path),
          plainText: text,
        ),
      );
    }

    void visitNested(
      List<MarkdownBlock> blocks,
      int blockIndex,
      List<MarkdownPathStep> basePath,
    ) {
      for (var c = 0; c < blocks.length; c++) {
        visitBlock(blocks[c], blockIndex, [...basePath, ChildStep(c)]);
      }
    }

    void visitList(
      ListBlock block,
      int blockIndex,
      List<MarkdownPathStep> basePath,
    ) {
      for (var i = 0; i < block.items.length; i++) {
        final item = block.items[i];
        final itemPath = [...basePath, ListItemStep(i)];
        addRuns(item.runs, blockIndex, itemPath);
        visitNested(item.children, blockIndex, itemPath);
      }
    }

    void visitBlock(
      MarkdownBlock block,
      int blockIndex,
      List<MarkdownPathStep> basePath,
    ) {
      switch (block) {
        case ParagraphBlock(:final runs):
          addRuns(runs, blockIndex, basePath);
        case HeadingBlock(:final runs):
          addRuns(runs, blockIndex, basePath);
        case ListBlock():
          visitList(block, blockIndex, basePath);
        case BlockquoteBlock(:final blocks):
          visitNested(blocks, blockIndex, basePath);
        case CodeBlock(:final text):
          if (text.isNotEmpty) {
            containers.add(
              MarkdownSearchContainer(
                blockIndex: blockIndex,
                path: List.unmodifiable(basePath),
                plainText: text,
              ),
            );
          }
        case TableBlock(:final headers, :final rows):
          for (var c = 0; c < headers.length; c++) {
            addRuns(headers[c].runs, blockIndex, [
              ...basePath,
              TableHeaderStep(c),
            ]);
          }
          for (var r = 0; r < rows.length; r++) {
            for (var c = 0; c < rows[r].length; c++) {
              addRuns(rows[r][c].runs, blockIndex, [
                ...basePath,
                TableCellStep(r, c),
              ]);
            }
          }
        case ImageBlock() || RawLiteralBlock() || HorizontalRuleBlock():
          break;
      }
    }

    final blocks = document.blocks;
    for (var i = 0; i < blocks.length; i++) {
      visitBlock(blocks[i], i, const []);
    }
    return MarkdownSearchIndex._(containers);
  }

  MarkdownSearchIndex._(this.containers);

  final List<MarkdownSearchContainer> containers;

  /// Scans every container in order; literal queries use case-folded
  /// substring scan (non-overlapping), regex queries [RegExp.allMatches]
  /// skipping zero-length matches. Throws [MarkdownSearchException] when a
  /// regex pattern cannot compile.
  List<MarkdownSearchHit> search(MarkdownSearchQuery query) {
    if (query.pattern.isEmpty) return const [];
    if (query.regex) {
      final RegExp re;
      try {
        re = RegExp(query.pattern, caseSensitive: query.caseSensitive);
      } on FormatException catch (e) {
        throw MarkdownSearchException(e.message);
      }
      return _collect((text) => re.allMatches(text));
    }
    final needle =
        query.caseSensitive ? query.pattern : query.pattern.toLowerCase();
    if (needle.isEmpty) return const [];
    return _collect((text) sync* {
      final source = query.caseSensitive ? text : text.toLowerCase();
      var from = 0;
      while (true) {
        final idx = source.indexOf(needle, from);
        if (idx < 0) break;
        yield RegExpMatch?._(idx, idx + needle.length); // replaced below
        from = idx + needle.length;
      }
    });
  }

  List<MarkdownSearchHit> _collect(
    Iterable<(int, int)> Function(String text) matcher,
  ) {
    final hits = <MarkdownSearchHit>[];
    for (var c = 0; c < containers.length; c++) {
      for (final (start, end) in matcher(containers[c].plainText)) {
        if (start >= end) continue;
        hits.add(MarkdownSearchHit(container: c, start: start, end: end));
        if (hits.length >= kMarkdownSearchMaxHits) return hits;
      }
    }
    return hits;
  }

  /// Highlight context resolving [hits]; the hit at [activeOrdinal] paints as
  /// the active match (-1 = none).
  MarkdownSearchHighlightContext highlightsFor(
    List<MarkdownSearchHit> hits, {
    int activeOrdinal = -1,
  }) =>
      MarkdownSearchHighlightContext.of(this, hits, activeOrdinal: activeOrdinal);
}
```

IMPORTANT correction while implementing — the two `_collect` call sites above sketch intent; the actual implementation must be exactly:

```dart
  List<MarkdownSearchHit> search(MarkdownSearchQuery query) {
    if (query.pattern.isEmpty) return const [];
    if (query.regex) {
      final RegExp re;
      try {
        re = RegExp(query.pattern, caseSensitive: query.caseSensitive);
      } on FormatException catch (e) {
        throw MarkdownSearchException(e.message);
      }
      return _collect((text) {
        return re.allMatches(text).map((m) => (m.start, m.end));
      });
    }
    final needle =
        query.caseSensitive ? query.pattern : query.pattern.toLowerCase();
    if (needle.isEmpty) return const [];
    return _collect((text) {
      final source = query.caseSensitive ? text : text.toLowerCase();
      final ranges = <(int, int)>[];
      var from = 0;
      while (true) {
        final idx = source.indexOf(needle, from);
        if (idx < 0) break;
        ranges.add((idx, idx + needle.length));
        from = idx + needle.length;
      }
      return ranges;
    });
  }

  List<MarkdownSearchHit> _collect(
    Iterable<(int, int)> Function(String text) matcher,
  ) {
    final hits = <MarkdownSearchHit>[];
    for (var c = 0; c < containers.length; c++) {
      for (final (start, end) in matcher(containers[c].plainText)) {
        if (start >= end) continue; // skip zero-length regex matches
        hits.add(MarkdownSearchHit(container: c, start: start, end: end));
        if (hits.length >= kMarkdownSearchMaxHits) return hits;
      }
    }
    return hits;
  }
```

Append to the same file — the highlight-context implementation (string-encoded keys because Dart list identity defeats record keys):

```dart
/// [MarkdownHighlightContext] resolved from an index + hit list.
class MarkdownSearchHighlightContext implements MarkdownHighlightContext {
  factory MarkdownSearchHighlightContext.of(
    MarkdownSearchIndex index,
    List<MarkdownSearchHit> hits, {
    int activeOrdinal = -1,
  }) {
    final entries = <String, MarkdownContainerHighlights>{};
    TextRange? active;
    for (var i = 0; i < hits.length; i++) {
      final hit = hits[i];
      if (hit.container < 0 || hit.container >= index.containers.length) {
        continue;
      }
      final container = index.containers[hit.container];
      final key = encodeAddress(container.blockIndex, container.path);
      final entry = entries.putIfAbsent(
        key,
        () => const MarkdownContainerHighlights(ranges: []),
      );
      final range = TextRange(start: hit.start, end: hit.end);
      entries[key] = MarkdownContainerHighlights(
        ranges: [...entry.ranges, range],
        active: null,
      );
      if (i == activeOrdinal) active = range;
      // stash handled below via second pass
      _pendingActive[i] = key;
    }
    // Second pass attaches active to its entry (ranges may repeat addresses).
    if (active != null) {
      final key = _pendingActive[activeOrdinal]!;
      final entry = entries[key]!;
      entries[key] = MarkdownContainerHighlights(
        ranges: entry.ranges,
        active: active,
      );
    }
    return MarkdownSearchHighlightContext._(entries);
  }

  static final Map<int, String> _pendingActive = {};

  MarkdownSearchHighlightContext._(this._entries);

  final Map<String, MarkdownContainerHighlights> _entries;

  @override
  MarkdownContainerHighlights? forContainer(
    int blockIndex,
    List<MarkdownPathStep> path,
  ) =>
      _entries[encodeAddress(blockIndex, path)];

  static String encodeAddress(int blockIndex, List<MarkdownPathStep> path) {
    final buf = StringBuffer('$blockIndex');
    for (final step in path) {
      buf.write('|');
      switch (step) {
        case ListItemStep(:final item):
          buf.write('L$item');
        case ChildStep(:final index):
          buf.write('C$index');
        case TableHeaderStep(:final col):
          buf.write('H$col');
        case TableCellStep(:final row, :final col):
          buf.write('T${row}x$col');
      }
    }
    return buf.toString();
  }
}
```

CRITICAL simplification note: the `_pendingActive` static-map draft above is WRONG (shared mutable state). Implement instead with a single pass — collect `(key, range, isActive)` triples first, then fold:

```dart
  factory MarkdownSearchHighlightContext.of(
    MarkdownSearchIndex index,
    List<MarkdownSearchHit> hits, {
    int activeOrdinal = -1,
  }) {
    final folded = <String, ({List<TextRange> ranges, TextRange? active})>{};
    for (var i = 0; i < hits.length; i++) {
      final hit = hits[i];
      if (hit.container < 0 || hit.container >= index.containers.length) {
        continue;
      }
      final container = index.containers[hit.container];
      final key = encodeAddress(container.blockIndex, container.path);
      final range = TextRange(start: hit.start, end: hit.end);
      final prev = folded[key];
      folded[key] = (
        ranges: [...?(prev?.ranges), range],
        active: i == activeOrdinal ? range : prev?.active,
      );
    }
    return MarkdownSearchHighlightContext._({
      for (final e in folded.entries)
        e.key: MarkdownContainerHighlights(
          ranges: e.value.ranges,
          active: e.value.active,
        ),
    });
  }
```

Use this last single-pass version; delete the `_pendingActive` variant entirely when writing the file.

- [ ] **Step 4: Run tests**

Run: `cd client/packages/tp_markdown && flutter test test/markdown_search_index_test.dart && flutter test`
Expected: PASS (whole package suite stays green).

- [ ] **Step 5: Commit**

```bash
git add client/packages/tp_markdown/lib/src/search/markdown_search_index.dart \
  client/packages/tp_markdown/lib/src/render/inline_spans.dart \
  client/packages/tp_markdown/test/markdown_search_index_test.dart
git commit -m "feat(tp_markdown): rendered-text search index + highlight context"
```

---

### Task 3: Span splitting + threading through MarkdownView / registry / builders

**Files:**
- Modify: `client/packages/tp_markdown/lib/src/render/inline_spans.dart` (highlight emission + builder signatures)
- Modify: `client/packages/tp_markdown/lib/src/registry/block_widget_registry.dart`
- Modify: `client/packages/tp_markdown/lib/src/render/list_blockquote_blocks.dart`
- Modify: `client/packages/tp_markdown/lib/src/render/table_code_hr_blocks.dart`
- Modify: `client/packages/tp_markdown/lib/src/render/markdown_view.dart`
- Modify: `client/packages/tp_markdown/lib/src/render/virtual_markdown_view.dart` (compile-compat pass-through only)
- Test: `client/packages/tp_markdown/test/markdown_highlight_render_test.dart`

**Interfaces:**
- Consumes: Task 1 types, Task 2 nothing (views receive contexts directly).
- Produces:
  - `List<InlineSpan> inlineSpans(List<InlineRun> runs, MarkdownTokens tokens, TextStyle base, MarkdownResolvers resolvers, {MarkdownContainerHighlights? highlights})`
  - `Widget buildParagraph(ParagraphBlock, tokens, resolvers, {MarkdownContainerHighlights? highlights})`
  - `Widget buildHeading(HeadingBlock, tokens, resolvers, {MarkdownContainerHighlights? highlights})`
  - `Widget buildMergedParagraphs(List<ParagraphBlock>, tokens, resolvers, {List<MarkdownContainerHighlights?> highlights})`
  - `Widget buildList(..., {MarkdownHighlightContext? highlights, int blockIndex = 0, List<MarkdownPathStep> basePath = const [], int depth = 0})`
  - `typedef MarkdownNestedViewBuilder = Widget Function(MarkdownDocument document, List<MarkdownPathStep> basePath)`
  - `Widget buildBlockquote(BlockquoteBlock, tokens, {required MarkdownNestedViewBuilder nestedView, MarkdownHighlightContext? highlights, int blockIndex = 0, List<MarkdownPathStep> basePath = const []})`
  - `Widget buildTable(TableBlock, tokens, resolvers, {MarkdownHighlightContext? highlights, int blockIndex = 0, List<MarkdownPathStep> basePath = const []})`
  - `Widget buildCodeBlock(CodeBlock, tokens, {MarkdownHighlightContext? highlights, int blockIndex = 0, List<MarkdownPathStep> basePath = const []})`
  - `typedef BlockWidgetBuilder = Widget Function(MarkdownBlock, MarkdownTokens, MarkdownResolvers, MarkdownStrings, MarkdownHighlightContext?, int blockIndex, List<MarkdownPathStep> basePath)`; `registry.build(..., {highlights, blockIndex = 0, basePath = const []})`
  - `MarkdownView({…, MarkdownHighlightContext? highlights, int blockIndex = 0, List<MarkdownPathStep> basePath = const []})`
  - `Text buildHighlightedCode(String code, TextStyle base, MarkdownTokens tokens, MarkdownContainerHighlights? highlights)` (code-block body helper)

- [ ] **Step 1: Write the failing test**

```dart
// client/packages/tp_markdown/test/markdown_highlight_render_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';
import 'package:tp_markdown/src/render/highlight_context.dart';

MarkdownContainerHighlights _hl({required List<TextRange> ranges, TextRange? active}) =>
    MarkdownContainerHighlights(ranges: ranges, active: active);

class _Ctx implements MarkdownHighlightContext {
  _Ctx(this.map);
  final Map<int, MarkdownContainerHighlights> map;

  @override
  MarkdownContainerHighlights? forContainer(int blockIndex, path) => map[blockIndex];
}

List<Text> _richParagraphTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .where((t) => t.textSpan != null)
    .toList();

String _spanText(InlineSpan span) {
  if (span is TextSpan) {
    return (span.text ?? '') +
        (span.children ?? []).map(_spanText).join();
  }
  return '';
}

bool _hasBackgroundOn(InlineSpan span, Color color) {
  if (span is! TextSpan) return false;
  if (span.style?.backgroundColor == color) return true;
  return (span.children ?? []).any((c) => _hasBackgroundOn(c, color));
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    MarkdownDocument doc,
    MarkdownHighlightContext? ctx,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MarkdownView(
          document: doc,
          tokens: MarkdownTokens.test(),
          highlights: ctx,
        ),
      ),
    ));
  }

  testWidgets('splits a TextRun around a match with wash background',
      (tester) async {
    await pump(
      tester,
      const MarkdownDocument(blocks: [
        ParagraphBlock(runs: [TextRun('hello brave world')])
      ]),
      _Ctx({
        0: _hl(ranges: [TextRange(start: 12, end: 17)]),
      }),
    );
    final para = _richParagraphTexts(tester)
        .firstWhere((t) => _spanText(t.textSpan!).contains('brave'));
    final wash = MarkdownTokens.test().matchHighlightColor;
    expect(_hasBackgroundOn(para.textSpan!, wash), isTrue);
    expect(_spanText(para.textSpan!), 'hello brave world');
  });

  testWidgets('match crossing bold boundary highlights both sides',
      (tester) async {
    await pump(
      tester,
      const MarkdownDocument(blocks: [
        ParagraphBlock(runs: [
          TextRun('Hel'),
          StrongRun(children: [TextRun('lo World')]),
        ])
      ]),
      _Ctx({
        0: _hl(ranges: [TextRange(start: 0, end: 9)]),
      }),
    );
    final para = _richParagraphTexts(tester)
        .firstWhere((t) => _spanText(t.textSpan!).contains('lo World'));
    final tokens = MarkdownTokens.test();
    expect(_hasBackgroundOn(para.textSpan!, tokens.matchHighlightColor), isTrue);
    // Bold half keeps strong weight under the wash.
    bool hasWashedBold(InlineSpan s) => s is TextSpan &&
        s.style?.backgroundColor == tokens.matchHighlightColor &&
        s.style?.fontWeight == FontWeight.w700;
    bool walk(InlineSpan s) =>
        hasWashedBold(s) || (s.children ?? []).any(walk);
    expect(walk(para.textSpan!), isTrue);
  });

  testWidgets('active range uses the stronger wash', (tester) async {
    await pump(
      tester,
      const MarkdownDocument(blocks: [
        ParagraphBlock(runs: [TextRun('one two')])
      ]),
      _Ctx({
        0: _hl(
            ranges: [TextRange(start: 0, end: 3), TextRange(start: 4, end: 7)],
            active: const TextRange(start: 4, end: 7)),
      }),
    );
    final para = _richParagraphTexts(tester)
        .firstWhere((t) => _spanText(t.textSpan!) == 'one two');
    final tokens = MarkdownTokens.test();
    expect(
        _hasBackgroundOn(para.textSpan!, tokens.matchHighlightActiveColor),
        isTrue);
  });

  testWidgets('list item + table cell + code text get highlights via paths',
      (tester) async {
    final ctx = _Ctx({
      1: _hl(ranges: [TextRange(start: 5, end: 10)]), // list item runs
      2: _hl(ranges: [TextRange(start: 5, end: 9)]), // table cell
      3: _hl(ranges: [TextRange(start: 6, end: 11)]), // code text
    });
    await pump(
      tester,
      const MarkdownDocument(blocks: [
        ParagraphBlock(runs: [TextRun('plain')]),
        ListBlock(ordered: false, items: [
          ContentListItem(runs: [TextRun('alpha world')])
        ]),
        TableBlock(headers: [
          InlineDocument(runs: [TextRun('h')])
        ], rows: [
          [InlineDocument(runs: [TextRun('cell world')])]
        ]),
        CodeBlock(language: '', text: 'code world\n'),
      ]),
      ctx,
    );
    final tokens = MarkdownTokens.test();
    final washed = _richParagraphTexts(tester)
        .where((t) => _hasBackgroundOn(t.textSpan!, tokens.matchHighlightColor))
        .map((t) => _spanText(t.textSpan!))
        .toList();
    expect(washed.join('\n'), contains('world')); // item
    expect(washed.join('\n'), contains('world')); // cell + code share text
    expect(washed.any((s) => s.contains('alpha')), isTrue);
    expect(washed.any((s) => s.contains('cell')), isTrue);
  });

  testWidgets('null context renders identically (no wash spans)', (tester) async {
    await pump(
      tester,
      const MarkdownDocument(blocks: [
        ParagraphBlock(runs: [TextRun('hello world')])
      ]),
      null,
    );
    final tokens = MarkdownTokens.test();
    final any = _richParagraphTexts(tester)
        .any((t) => _hasBackgroundOn(t.textSpan!, tokens.matchHighlightColor));
    expect(any, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/tp_markdown && flutter test test/markdown_highlight_render_test.dart`
Expected: FAIL — `highlights` parameter unknown on `MarkdownView`.

- [ ] **Step 3: Implement inline_spans.dart**

Replace/add in `inline_spans.dart` (imports add `../render/highlight_context.dart` — same directory, just `'highlight_context.dart'`; and `dart:ui` not needed, TextRange comes from painting via material):

```dart
import 'highlight_context.dart';
```

New public API + internals (place after `inlineSpan`):

```dart
List<InlineSpan> inlineSpans(
  List<InlineRun> runs,
  MarkdownTokens tokens,
  TextStyle base,
  MarkdownResolvers resolvers, {
  MarkdownContainerHighlights? highlights,
}) {
  if (highlights == null || highlights.ranges.isEmpty) {
    return [for (final run in runs) inlineSpan(run, tokens, base, resolvers)];
  }
  final cursor = _HighlightCursor(highlights);
  final out = <InlineSpan>[];
  _emitHighlightedRuns(runs, tokens, base, resolvers, cursor, out);
  return out;
}

/// Mutable plain-text offset shared across one container's span build.
class _HighlightCursor {
  _HighlightCursor(this.highlights);

  final MarkdownContainerHighlights highlights;
  int offset = 0;

  TextStyle styleFor(int start, int end, TextStyle base, MarkdownTokens t) {
    final covered =
        highlights.ranges.any((r) => r.start <= start && end <= r.end);
    if (!covered) return base;
    final active = highlights.active;
    final isActive = active != null && active.start <= start && end <= active.end;
    return t.matchHighlight(base, active: isActive);
  }
}

void _emitHighlightedRuns(
  List<InlineRun> runs,
  MarkdownTokens tokens,
  TextStyle base,
  MarkdownResolvers resolvers,
  _HighlightCursor cursor,
  List<InlineSpan> out,
) {
  for (final run in runs) {
    switch (run) {
      case TextRun(:final text):
        _emitSplitLeaf(text, base, tokens, cursor, out);
      case CodeRun(:final text):
        _emitSplitLeaf(text, tokens.inlineCodeAt(base), tokens, cursor, out);
      case StrongRun(:final children):
        _emitMarked(children, tokens.strongStyle(base), tokens, resolvers,
            cursor, out);
      case EmphasisRun(:final children):
        _emitMarked(children, tokens.emphasisStyle(base), tokens, resolvers,
            cursor, out);
      case StrikeRun(:final children):
        _emitMarked(children, tokens.strikeStyle(base), tokens, resolvers,
            cursor, out);
      case LinkRun(:final url, :final children):
        final start = out.length;
        _emitHighlightedRuns(
            children, tokens, tokens.link, resolvers, cursor, out);
        final recognizer = resolvers.createLinkRecognizer?.call(url);
        final cursorIcon = resolvers.onLinkTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click;
        for (var i = start; i < out.length; i++) {
          out[i] = _withLinkGesture(out[i], recognizer, cursorIcon);
        }
      case ImageRun():
        break; // WidgetSpan — outside the text flow, unhighlightable.
    }
  }
}

void _emitMarked(
  List<InlineRun> children,
  TextStyle style,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers,
  _HighlightCursor cursor,
  List<InlineSpan> out,
) {
  final inner = <InlineSpan>[];
  _emitHighlightedRuns(children, tokens, style, resolvers, cursor, inner);
  out.add(TextSpan(style: style, children: inner));
}

void _emitSplitLeaf(
  String text,
  TextStyle style,
  MarkdownTokens tokens,
  _HighlightCursor cursor,
  List<InlineSpan> out,
) {
  final start = cursor.offset;
  final end = start + text.length;
  final cuts = <int>{start, end};
  for (final r in cursor.highlights.ranges) {
    if (r.start < end && r.end > start) {
      cuts.add(r.start.clamp(start, end));
      cuts.add(r.end.clamp(start, end));
    }
  }
  final points = cuts.toList()..sort();
  for (var i = 0; i < points.length - 1; i++) {
    final s = points[i];
    final e = points[i + 1];
    if (e <= s) continue;
    out.add(TextSpan(
      text: text.substring(s - start, e - start),
      style: cursor.styleFor(s, e, style, tokens),
    ));
  }
  cursor.offset = end;
}
```

Update the three paragraph/heading builders:

```dart
Widget buildMergedParagraphs(
  List<ParagraphBlock> paragraphs,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers, {
  List<MarkdownContainerHighlights?> highlights = const [],
}) {
  MarkdownContainerHighlights? at(int i) =>
      i < highlights.length ? highlights[i] : null;
  final spans = <InlineSpan>[];
  for (var i = 0; i < paragraphs.length; i++) {
    if (i > 0) {
      final fontSize = tokens.body.fontSize ?? 14.0;
      final gap = gapBetween(
        MarkdownBlockKind.paragraph,
        MarkdownBlockKind.paragraph,
        tokens,
      );
      spans.add(
        TextSpan(
          text: '\n\n',
          style: tokens.body.copyWith(height: gap / fontSize),
        ),
      );
    }
    spans.add(
      TextSpan(
        style: tokens.body,
        children: inlineSpans(paragraphs[i].runs, tokens, tokens.body,
            resolvers, highlights: at(i)),
      ),
    );
  }
  return Text.rich(
    TextSpan(style: tokens.body, children: spans),
    strutStyle: forcedStrut(tokens.body),
  );
}

Widget buildParagraph(
  ParagraphBlock block,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers, {
  MarkdownContainerHighlights? highlights,
}) {
  return Text.rich(
    TextSpan(
      style: tokens.body,
      children: inlineSpans(block.runs, tokens, tokens.body, resolvers,
          highlights: highlights),
    ),
    strutStyle: forcedStrut(tokens.body),
  );
}

Widget buildHeading(
  HeadingBlock block,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers, {
  MarkdownContainerHighlights? highlights,
}) {
  final style = headingStyleForLevel(tokens, block.level);
  return Text.rich(
    TextSpan(
      style: style,
      children: inlineSpans(block.runs, tokens, style, resolvers,
          highlights: highlights),
    ),
    strutStyle: forcedStrut(style),
  );
}
```

Add the code-text helper (used by Task 3's code-block change):

```dart
/// Code-block body text with optional match highlighting (single leaf split).
Text buildHighlightedCode(
  String code,
  TextStyle base,
  MarkdownTokens tokens,
  MarkdownContainerHighlights? highlights,
) {
  if (highlights == null || highlights.ranges.isEmpty) {
    return Text(code, style: base, softWrap: false, strutStyle: forcedStrut(base));
  }
  final cursor = _HighlightCursor(highlights);
  final out = <InlineSpan>[];
  _emitSplitLeaf(code, base, tokens, cursor, out);
  return Text.rich(
    TextSpan(style: base, children: out),
    softWrap: false,
    strutStyle: forcedStrut(base),
  );
}
```

- [ ] **Step 4: Implement registry + list/blockquote + table/code + MarkdownView**

`block_widget_registry.dart` full replacement of typedef/build/builtIn:

```dart
typedef BlockWidgetBuilder = Widget Function(
  MarkdownBlock block,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers,
  MarkdownStrings strings,
  MarkdownHighlightContext? highlights,
  int blockIndex,
  List<MarkdownPathStep> basePath,
);

  Widget build(
    MarkdownBlock block,
    MarkdownTokens tokens,
    MarkdownResolvers resolvers,
    MarkdownStrings strings, {
    MarkdownHighlightContext? highlights,
    int blockIndex = 0,
    List<MarkdownPathStep> basePath = const [],
  }) {
    final builder = _builders[block.runtimeType];
    if (builder != null) {
      return builder(block, tokens, resolvers, strings, highlights, blockIndex,
          basePath);
    }
    return Text(block.runtimeType.toString());
  }

  factory BlockWidgetRegistry.builtIn() {
    final registry = BlockWidgetRegistry._();

    registry.register<ParagraphBlock>(
        (block, tokens, resolvers, _, highlights, __, ___) {
      return buildParagraph(block as ParagraphBlock, tokens, resolvers,
          highlights: resolveSelf(highlights, __, ___));
    });
```

Wait — paragraph resolution needs the context lookup; do NOT put resolution inside registry lambdas (they lack basePath semantics clarity). Resolution happens INSIDE each builder which receives context+blockIndex+basePath uniformly. Simplify: every registration forwards verbatim:

```dart
  factory BlockWidgetRegistry.builtIn() {
    final registry = BlockWidgetRegistry._();

    registry.register<ParagraphBlock>(
      (block, tokens, resolvers, _, hl, bi, p) => buildParagraph(
        block as ParagraphBlock, tokens, resolvers,
        highlights: hl?.forContainer(bi, p)),
    );

    registry.register<HeadingBlock>(
      (block, tokens, resolvers, _, hl, bi, p) => buildHeading(
        block as HeadingBlock, tokens, resolvers,
        highlights: hl?.forContainer(bi, p)),
    );

    registry.register<ListBlock>((block, tokens, resolvers, strings, hl, bi, p) {
      return buildList(
        block as ListBlock, tokens, resolvers,
        highlights: hl, blockIndex: bi, basePath: p,
        nestedView: (document, nestedBase) => MarkdownView(
          document: document, tokens: tokens, resolvers: resolvers,
          strings: strings, registry: registry,
          highlights: hl, blockIndex: bi, basePath: nestedBase,
        ),
      );
    });

    registry.register<BlockquoteBlock>(
        (block, tokens, resolvers, strings, hl, bi, p) {
      return buildBlockquote(
        block as BlockquoteBlock, tokens,
        highlights: hl, blockIndex: bi, basePath: p,
        nestedView: (document, nestedBase) => MarkdownView(
          document: document, tokens: tokens, resolvers: resolvers,
          strings: strings, registry: registry,
          highlights: hl, blockIndex: bi, basePath: nestedBase,
        ),
      );
    });

    registry.register<HorizontalRuleBlock>((_, tokens, __, ___, ____, _____, ______) {
      return buildHorizontalRule(tokens);
    });

    registry.register<CodeBlock>(
        (block, tokens, _, __, hl, bi, p) =>
            buildCodeBlock(block as CodeBlock, tokens,
                highlights: hl, blockIndex: bi, basePath: p));

    registry.register<TableBlock>(
        (block, tokens, resolvers, _, hl, bi, p) => buildTable(
            block as TableBlock, tokens, resolvers,
            highlights: hl, blockIndex: bi, basePath: p));

    registry.register<ImageBlock>((block, tokens, resolvers, _, __, ___, ____) {
      return buildImageBlock(block as ImageBlock, tokens, resolvers);
    });

    registry.register<RawLiteralBlock>(
        (block, tokens, _, __, ___, ____, _____) {
      return buildRawLiteralBlock(block as RawLiteralBlock, tokens);
    });

    return registry;
  }
```

(Keep imports: add `../render/highlight_context.dart`.)

`list_blockquote_blocks.dart` replacement:

```dart
typedef MarkdownNestedViewBuilder = Widget Function(
  MarkdownDocument document,
  List<MarkdownPathStep> basePath,
);

Widget buildBlockquote(
  BlockquoteBlock block,
  MarkdownTokens tokens, {
  required MarkdownNestedViewBuilder nestedView,
  MarkdownHighlightContext? highlights,
  int blockIndex = 0,
  List<MarkdownPathStep> basePath = const [],
}) {
  return DecoratedBox(
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: tokens.borderColor, width: 3)),
    ),
    child: Padding(
      padding: const EdgeInsets.only(left: 12),
      child: nestedView(MarkdownDocument(blocks: block.blocks), basePath),
    ),
  );
}

Widget buildList(
  ListBlock block,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers, {
  required MarkdownNestedViewBuilder nestedView,
  MarkdownHighlightContext? highlights,
  int blockIndex = 0,
  List<MarkdownPathStep> basePath = const [],
  int depth = 0,
}) {
  return _MarkdownList(
    ordered: block.ordered,
    items: block.items,
    tokens: tokens,
    resolvers: resolvers,
    nestedView: nestedView,
    highlights: highlights,
    blockIndex: blockIndex,
    basePath: basePath,
    depth: depth,
  );
}
```

`_MarkdownList`: add fields `highlights/blockIndex/basePath`; `_buildItem` becomes:

```dart
  Widget _buildItem(ContentListItem item, int index) {
    final marker = _marker(item, index);
    final itemPath = [...basePath, ListItemStep(index)];
    final content = Text.rich(
      TextSpan(
        style: tokens.body,
        children: inlineSpans(
          item.runs, tokens, tokens.body, resolvers,
          highlights: highlights?.forContainer(blockIndex, itemPath),
        ),
      ),
      strutStyle: forcedStrut(tokens.body),
    );
    // ... row assembly unchanged ...

    // children loop becomes:
    var ci = 0;
    for (final child in item.children) {
      final childPath = [...itemPath, ChildStep(ci)];
      ci++;
      switch (child) {
        case ListBlock(:final ordered, :final items) when false:
          break; // unreachable guard kept simple below
        default:
      }
      // Actual dispatch mirrors original:
    }
```

Concretely replace the original children `switch` with:

```dart
          var childIndex = 0;
          for (final child in item.children) {
            final childWidgets = switch (child) {
              ListBlock(:final ordered, :final items) => [
                  buildList(
                    ListBlock(ordered: ordered, items: items),
                    tokens,
                    resolvers,
                    nestedView: nestedView,
                    highlights: highlights,
                    blockIndex: blockIndex,
                    basePath: [...basePath, ListItemStep(index)],
                    depth: depth + 1,
                  ),
                ],
              _ => [
                  Padding(
                    padding: EdgeInsets.only(left: tokens.listIndent),
                    child: nestedView(
                      MarkdownDocument(blocks: [child]),
                      [...basePath, ListItemStep(index), ChildStep(childIndex)],
                    ),
                  ),
                ],
            };
            childIndex++;
            yield_ = childWidgets; // see full loop below
          }
```

Final concrete `_buildItem` tail (write exactly this, no pseudo-yield):

```dart
    if (item.children.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: depth * tokens.listIndent),
        child: row,
      );
    }

    final childRows = <Widget>[];
    var childIndex = 0;
    for (final child in item.children) {
      final itemPath = [...basePath, ListItemStep(index)];
      switch (child) {
        case ListBlock(:final ordered, :final items):
          childRows.add(
            buildList(
              ListBlock(ordered: ordered, items: items),
              tokens,
              resolvers,
              nestedView: nestedView,
              highlights: highlights,
              blockIndex: blockIndex,
              basePath: itemPath,
              depth: depth + 1,
            ),
          );
        default:
          childRows.add(
            Padding(
              padding: EdgeInsets.only(left: tokens.listIndent),
              child: nestedView(
                MarkdownDocument(blocks: [child]),
                [...itemPath, ChildStep(childIndex)],
              ),
            ),
          );
      }
      childIndex++;
    }

    return Padding(
      padding: EdgeInsets.only(left: depth * tokens.listIndent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row,
          if (tokens.listItemGap > 0) SizedBox(height: tokens.listItemGap),
          ...childRows,
        ],
      ),
    );
  }
```

(Note: compute `itemPath` once above `content` and reuse.)

`table_code_hr_blocks.dart`:

```dart
Widget buildTable(
  TableBlock block,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers, {
  MarkdownHighlightContext? highlights,
  int blockIndex = 0,
  List<MarkdownPathStep> basePath = const [],
}) {
  return _MarkdownTable(
    headers: block.headers,
    rows: block.rows,
    tokens: tokens,
    resolvers: resolvers,
    highlights: highlights,
    blockIndex: blockIndex,
    basePath: basePath,
  );
}

Widget buildCodeBlock(
  CodeBlock block,
  MarkdownTokens tokens, {
  MarkdownHighlightContext? highlights,
  int blockIndex = 0,
  List<MarkdownPathStep> basePath = const [],
}) {
  return _MarkdownCodeBlock(
    language: block.language ?? '',
    code: block.text,
    tokens: tokens,
    highlights: highlights?.forContainer(blockIndex, basePath),
  );
}
```

`_MarkdownTable`: add fields `highlights/blockIndex/basePath`; `cellRow` gains `{int? rowIndex}`; per-cell resolution:

```dart
              child: Text.rich(
                TextSpan(
                  style: cellStyle,
                  children: inlineSpans(
                    c < cells.length ? cells[c].runs : const [],
                    tokens,
                    cellStyle,
                    resolvers,
                    highlights: highlights?.forContainer(
                      blockIndex,
                      rowIndex == null
                          ? [...basePath, TableHeaderStep(c)]
                          : [...basePath, TableCellStep(rowIndex, c)],
                    ),
                  ),
                ),
                strutStyle: forcedStrut(cellStyle),
              ),
```

(call sites: `cellRow(headers, isHeader: true)` keeps null rowIndex; body loop passes `rowIndex: r` — adjust `for (final row in rows)` to indexed loop.)

`_MarkdownCodeBlock`: add field `final MarkdownContainerHighlights? highlights;`; `_codeBody` becomes:

```dart
  Widget _codeBody(String code) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: buildHighlightedCode(code, widget.tokens.codeBlock, widget.tokens, widget.highlights),
      ),
    );
  }
```

Masked/collapsed caveat (spec §error-handling): when collapsed shows only first lines, ranges computed against FULL text misalign. Guard: in `_buildMaskedBody`, when `widget.highlights != null` force the expanded/full body path (auto-expand masked blocks carrying matches):

At top of `build()` after computing `huge`/`mode`:

```dart
    final forceFull = widget.highlights != null &&
        widget.highlights!.ranges.isNotEmpty &&
        huge &&
        mode != ContentDisplayMode.flatten;
```

and use `if (!huge || mode == ContentDisplayMode.flatten || forceFull)` for the natural-height branch. (Height wash does not affect layout; cache unaffected.)

`markdown_view.dart`: add params + loop threading:

```dart
  const MarkdownView({
    super.key,
    required this.document,
    required this.tokens,
    this.resolvers = const MarkdownResolvers(),
    this.strings = MarkdownStrings.english,
    this.registry,
    this.highlights,
    this.blockIndex = 0,
    this.basePath = const [],
  });

  final MarkdownHighlightContext? highlights;

  /// Top-level index reported by every block here (nested views reuse the
  /// parent's; nesting extends [basePath] instead).
  final int blockIndex;
  final List<MarkdownPathStep> basePath;
```

Loop paragraph branch:

```dart
        final perParagraph = [
          for (final _ in run)
            widget.highlights?.forContainer(widget.blockIndex, widget.basePath),
        ];
        children.add(
          wrapHorizontal(
            MarkdownBlockKind.paragraph,
            run.length == 1
                ? buildParagraph(run.first, tokens, resolvers,
                    highlights: perParagraph[0])
                : buildMergedParagraphs(run, tokens, resolvers,
                    highlights: perParagraph),
          ),
        );
```

Registry branch:

```dart
          reg.build(
            block, tokens, resolvers, strings,
            highlights: widget.highlights,
            blockIndex: widget.blockIndex,
            basePath: widget.basePath,
          ),
```

`virtual_markdown_view.dart` compile-compat: extend `_MarkdownUnit.build` signature to mirror registry and update `_computeUnits` closures + `_buildUnit` call to forward placeholders until Task 4:

```dart
  final Widget Function(
    MarkdownTokens,
    MarkdownResolvers,
    MarkdownResolvers resolversUnusedPlaceholderRemoved, // NO — exact below
  )
```

Exact interim typedef:

```dart
  final Widget Function(
    MarkdownTokens tokens,
    MarkdownResolvers resolvers,
    MarkdownStrings strings,
    BlockWidgetRegistry reg,
  ) build;
```

stays UNCHANGED in this task; only the two call sites change:

- merged-run closure: `build: (tokens, resolvers, strings, reg) => run.length == 1 ? buildParagraph(run.first, tokens, resolvers) : buildMergedParagraphs(run, tokens, resolvers)` → append `highlights: null` / `highlights: const []`.
- single-block closure: `reg.build(block, tokens, resolvers, strings)` → `reg.build(block, tokens, resolvers, strings)`.
(no change needed actually since new params have defaults) — VERIFY: with named-default params added everywhere, existing positional calls compile untouched. **Conclusion: virtual view needs ZERO edits this task.** Skip that file entirely in Task 3.

- [ ] **Step 5: Run tests**

Run: `cd client/packages/tp_markdown && flutter test`
Expected: ALL PASS including prior suites (default params keep old call sites valid).

- [ ] **Step 6: Commit**

```bash
git add client/packages/tp_markdown
git commit -m "feat(tp_markdown): highlight-aware span splitting threaded through views/builders"
```

---

### Task 4: VirtualMarkdownView threading — units record covered block ranges

**Files:**
- Modify: `client/packages/tp_markdown/lib/src/render/virtual_markdown_view.dart`
- Test: `client/packages/tp_markdown/test/virtual_markdown_view_highlight_test.dart`

**Interfaces:**
- Consumes: Task 3 signatures.
- Produces: `VirtualMarkdownView({…, MarkdownHighlightContext? highlights})`; `_MarkdownUnit {int firstBlockIndex; int lastBlockIndex;}` (private, but reveal in Task 5 relies on mapping method `_unitForBlock(int blockIndex)`).

- [ ] **Step 1: Write the failing test**

```dart
// client/packages/tp_markdown/test/virtual_markdown_view_highlight_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/src/render/highlight_context.dart';
import 'package:tp_markdown/tp_markdown.dart';

class _Ctx implements MarkdownHighlightContext {
  _Ctx(this.map);
  final Map<int, MarkdownContainerHighlights> map;
  @override
  MarkdownContainerHighlights? forContainer(int blockIndex, path) => map[blockIndex];
}

String _flat(InlineSpan s) =>
    s is TextSpan ? (s.text ?? '') + (s.children ?? []).map(_flat).join() : '';

void main() {
  testWidgets('flatten-mode virtual view paints highlights in visible window',
      (tester) async {
    final blocks = <MarkdownBlock>[
      for (var i = 0; i < 60; i++)
        ParagraphBlock(runs: [TextRun('para $i needle')]),
    ];
    final wash = MarkdownTokens.test().matchHighlightColor;
    final ctx = _Ctx({30: MarkdownContainerHighlights(ranges: [
      const TextRange(start: 7, end: 12),
    ])});

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: VirtualMarkdownView(
            document: MarkdownDocument(blocks: blocks),
            tokens: MarkdownTokens.test(),
            flatten: true,
            highlights: ctx,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Jump near block 30 so it mounts.
    tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(1400);
    await tester.pumpAndSettle();

    bool hasWash(InlineSpan s) => s is TextSpan &&
        s.style?.backgroundColor == wash ||
        (s.children ?? []).any(hasWash);

    final found = tester.widgetList<Text>(find.byType(Text)).any((t) =>
        t.textSpan != null && _flat(t.textSpan!).contains('needle') && hasWash(t.textSpan!));
    expect(found, isTrue);
  });
}
```

If the jump offset misses block 30 (estimate-dependent), instead assert: scrolling through the WHOLE document in steps mounts a washed span at some point — implement helper loop `for offsets in [0..N*step] jumpTo + pump` breaking when found. Use whichever makes the test deterministic; prefer the loop.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/tp_markdown && flutter test test/virtual_markdown_view_highlight_test.dart`
Expected: FAIL — no `highlights` param on `VirtualMarkdownView`.

- [ ] **Step 3: Implement**

In `virtual_markdown_view.dart`:

1. Import `highlight_context.dart`.
2. Widget param:

```dart
    this.highlights,
```
   field `final MarkdownHighlightContext? highlights;`

3. `_MarkdownUnit` gains:

```dart
  const _MarkdownUnit({
    required this.kind,
    required this.gapBefore,
    required this.build,
    this.firstBlockIndex = 0,
    this.lastBlockIndex = 0,
  });

  /// Top-level block indexes covered (merged paragraph runs span several).
  final int firstBlockIndex;
  final int lastBlockIndex;
```

4. `_computeUnits`: thread real indexes — paragraph branch:

```dart
        units.add(
          _MarkdownUnit(
            kind: MarkdownBlockKind.paragraph,
            gapBefore: _gapBefore(previous?.kind, MarkdownBlockKind.paragraph),
            firstBlockIndex: i,
            lastBlockIndex: end - 1,
            build: (tokens, resolvers, strings, reg) {
              final perParagraph = [
                for (final _ in run)
                  widget.highlights
                      ?.forContainer(i /* placeholder replaced below */, const []),
              ];
```

NO — closure can't reference loop variable `i` after mutation… it CAN via captured final local. Capture properly:

```dart
      if (block is ParagraphBlock) {
        var end = i + 1;
        while (end < blocks.length && blocks[end] is ParagraphBlock) {
          end++;
        }
        final run = blocks.sublist(i, end).cast<ParagraphBlock>();
        final first = i;
        final last = end - 1;
        final context = widget.highlights;
        units.add(
          _MarkdownUnit(
            kind: MarkdownBlockKind.paragraph,
            gapBefore: _gapBefore(previous?.kind, MarkdownBlockKind.paragraph),
            firstBlockIndex: first,
            lastBlockIndex: last,
            build: (tokens, resolvers, strings, reg) {
              final perParagraph = [
                for (var p = 0; p < run.length; p++)
                  context?.forContainer(first + p, const []),
              ];
              return run.length == 1
                  ? buildParagraph(run.first, tokens, resolvers,
                      highlights: perParagraph[0])
                  : buildMergedParagraphs(run, tokens, resolvers,
                      highlights: perParagraph);
            },
          ),
        );
        previous = run.last;
        i = end;
        continue;
      }
```

Single-block branch:

```dart
      final currentIndex = i;
      units.add(
        _MarkdownUnit(
          kind: block.kind,
          gapBefore: _gapBefore(previous?.kind, block.kind),
          firstBlockIndex: currentIndex,
          lastBlockIndex: currentIndex,
          build: (tokens, resolvers, strings, reg) => reg.build(
            block, tokens, resolvers, strings,
            highlights: widget.highlights,
            blockIndex: currentIndex,
            basePath: const [],
          ),
        ),
      );
```

NOTE: closures capture `widget.highlights` at COMPUTE time (initState/didUpdateWidget-on-document-change). Highlight changes must rebuild closures → add to `didUpdateWidget`:

```dart
    if (!identical(oldWidget.highlights, widget.highlights) ||
        oldWidget.document != widget.document) {
      _units = _computeUnits(widget.document);
      if (oldWidget.document != widget.document) {
        _cache.invalidateAll();
        _firstIndex = 0;
        _lastIndex = -1;
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      }
      _syncVisibleRange();
    }
```

(replacing the existing document-only branch; heights stay cached across highlight-only changes — background wash never affects layout.)

5. Expose unit mapping for Task 5 (private method):

```dart
  int _unitForBlock(int blockIndex) {
    for (var u = 0; u < _units.length; u++) {
      if (blockIndex < _units[u].firstBlockIndex) return -1... 
```

Exact:

```dart
  /// Index of the unit covering [blockIndex], or -1.
  int _unitForBlock(int blockIndex) {
    var lo = 0;
    var hi = _units.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final unit = _units[mid];
      if (blockIndex < unit.firstBlockIndex) {
        hi = mid - 1;
      } else if (blockIndex > unit.lastBlockIndex) {
        lo = mid + 1;
      } else {
        return mid;
      }
    }
    return -1;
  }
```

- [ ] **Step 4: Run tests**

Run: `cd client/packages/tp_markdown && flutter test`
Expected: PASS all.

- [ ] **Step 5: Commit**

```bash
git add client/packages/tp_markdown/lib/src/render/virtual_markdown_view.dart \
  client/packages/tp_markdown/test/virtual_markdown_view_highlight_test.dart
git commit -m "feat(tp_markdown): virtual markdown view threads highlight context per block"
```

---

### Task 5: MarkdownViewController — reveal a block

**Files:**
- Modify: `client/packages/tp_markdown/lib/src/render/virtual_markdown_view.dart`
- Test: `client/packages/tp_markdown/test/virtual_markdown_view_reveal_test.dart`

**Interfaces:**
- Produces: `class MarkdownViewController { Future<void> revealBlock(int blockIndex); void dispose(); }`; `VirtualMarkdownView({…, this.controller})`.

- [ ] **Step 1: Write the failing test**

```dart
// client/packages/tp_markdown/test/virtual_markdown_view_reveal_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

MarkdownDocument tallDoc(int n) => MarkdownDocument(blocks: [
      for (var i = 0; i < n; i++)
        ParagraphBlock(runs: [TextRun('block $i ${'filler text ' * 20}')]),
    ]);

Widget harness(MarkdownViewController controller, ScrollController outer) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          controller: outer,
          child: VirtualMarkdownView(
            document: tallDoc(80),
            tokens: MarkdownTokens.test(),
            flatten: true,
            controller: controller,
          ),
        ),
      ),
    );

void main() {
  testWidgets('revealBlock scrolls the parent viewport (flatten)',
      (tester) async {
    final controller = MarkdownViewController();
    final outer = ScrollController();
    await tester.pumpWidget(harness(controller, outer));
    await tester.pumpAndSettle();

    await controller.revealBlock(70);
    await tester.pumpAndSettle();
    expect(outer.offset, greaterThan(500));

    controller.dispose();
    outer.dispose();
  });

  testWidgets('revealBlock drives internal scroll (bounded)', (tester) async {
    final controller = MarkdownViewController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VirtualMarkdownView(
          document: tallDoc(80),
          tokens: MarkdownTokens.test(),
          maxHeight: 400,
          controller: controller,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await controller.revealBlock(70);
    await tester.pumpAndSettle();
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.pixels, greaterThan(500));

    controller.dispose();
  });

  testWidgets('reveal before mount is a safe no-op', (tester) async {
    final controller = MarkdownViewController();
    await controller.revealBlock(3); // no widget bound yet
    controller.dispose();
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/tp_markdown && flutter test test/virtual_markdown_view_reveal_test.dart`
Expected: FAIL — `MarkdownViewController` undefined.

- [ ] **Step 3: Implement**

Top-of-file addition (after imports) in `virtual_markdown_view.dart`:

```dart
/// Controller bound to one [VirtualMarkdownView]; reveals blocks by scrolling
/// the owning viewport (internal in bounded mode, parent scroll in flatten).
class MarkdownViewController {
  State<VirtualMarkdownView>? _state;

  bool get hasClients => _state != null;

  Future<void> revealBlock(int blockIndex) async {
    await _state?.revealBlockPublic(blockIndex);
  }

  /// Detach without disposing the bound view (safe to call repeatedly).
  void dispose() {
    if (_state != null) {
      _state = null;
    }
  }
}
```

Widget param + lifecycle in state:

```dart
    this.controller,
```
field: `final MarkdownViewController? controller;`

State additions:

```dart
  @override
  void initState() {
    super.initState();
    widget.controller?._attachInternal(this);
    // ... existing ...
  }

  @override
  void didUpdateWidget(covariant VirtualMarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detachInternal(this);
      widget.controller?._attachInternal(this);
    }
    // ... existing branches ...
  }

  @override
  void dispose() {
    widget.controller?._detachInternal(this);
    // ... existing ...
  }
```

Controller back-references (on MarkdownViewController): `void _attachInternal(State<VirtualMarkdownView> s) => _state = s;` / `void _detachInternal(State<VirtualMarkdownView> s) { if (identical(_state, s)) _state = null; }`

State reveal implementation:

```dart
  static const Duration _revealDuration = Duration(milliseconds: 180);
  static const double _revealCorrectionThreshold = 2.0;

  Future<void> revealBlockPublic(int blockIndex) async {
    final unit = _unitForBlock(blockIndex);
    if (unit < 0 || !mounted) return;
    await _revealTo(unit);
    if (!mounted) return;
    // Heights ahead may still be estimates; correct once they measure.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _revealCorrectionPass(unit);
      }
    });
  }

  Future<void> _revealTo(int unit) async {
    final contentOffset = _cache.offsetBefore(_units.length, unit);
    if (!widget.flatten) {
      if (!_scrollController.hasClients ||
          !_scrollController.position.hasViewportDimension) {
        return;
      }
      await _animateTo(_scrollController.position, contentOffset);
      return;
    }
    final position = _parentPosition;
    final renderObject = context.findRenderObject();
    if (position == null || !position.hasViewportDimension) return;
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final revealed = RenderAbstractViewport.of(renderObject)
        .getOffsetToReveal(renderObject, 0.0);
    await _animateTo(position, revealed.offset + contentOffset);
  }

  Future<void> _animateTo(ScrollPosition position, double contentOffset) async {
    final target = (contentOffset - position.viewportDimension * 0.25)
        .clamp(0.0, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 1.0) return;
    await position.animateTo(
      target,
      duration: _revealDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _revealCorrectionPass(int unit) {
    final contentOffset = _cache.offsetBefore(_units.length, unit);
    if (!widget.flatten) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target =
          (contentOffset - position.viewportDimension * 0.25).clamp(0.0, position.maxScrollExtent);
      if ((target - position.pixels).abs() >= _revealCorrectionThreshold) {
        position.jumpTo(target);
      }
      return;
    }
    final position = _parentPosition;
    final renderObject = context.findRenderObject();
    if (position == null || renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }
    final revealed = RenderAbstractViewport.of(renderObject)
        .getOffsetToReveal(renderObject, 0.0);
    final target = (revealed.offset + contentOffset - position.viewportDimension * 0.25)
        .clamp(0.0, position.maxScrollExtent);
    if ((target - position.pixels).abs() >= _revealCorrectionThreshold) {
      position.jumpTo(target);
    }
  }
```

- [ ] **Step 4: Run tests**

Run: `cd client/packages/tp_markdown && flutter test`
Expected: PASS all.

- [ ] **Step 5: Commit**

```bash
git add client/packages/tp_markdown/lib/src/render/virtual_markdown_view.dart \
  client/packages/tp_markdown/test/virtual_markdown_view_reveal_test.dart
git commit -m "feat(tp_markdown): MarkdownViewController reveal with measurement correction"
```

---

### Task 6: Package exports + green suite

**Files:**
- Modify: `client/packages/tp_markdown/lib/tp_markdown.dart`

**Interfaces:**
- Produces public exports: `highlight_context.dart`, `search/markdown_search_index.dart` (controller already exported via `virtual_markdown_view.dart`).

- [ ] **Step 1: Update exports**

Insert alphabetically in `tp_markdown.dart`:

```dart
export 'src/render/highlight_context.dart';
export 'src/render/markdown_view.dart';           // existing line, keep
export 'src/render/virtual_markdown_view.dart';   // existing line, keep
export 'src/search/markdown_search_index.dart';
```

(final ordering: place `highlight_context` before `markdown_view`, `search/...` after it.)

- [ ] **Step 2: Run full package suite + analyze**

Run: `cd client/packages/tp_markdown && flutter test && cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: PASS / no issues.

- [ ] **Step 3: Commit**

```bash
git add client/packages/tp_markdown/lib/tp_markdown.dart
git commit -m "feat(tp_markdown): export search + highlight API"
```

---

### Task 7: Extract MarkdownPreviewPane (pure refactor)

**Files:**
- Create: `client/lib/pages/workbench/markdown_preview_pane.dart`
- Modify: `client/lib/pages/workbench/file_editor_surface.dart` (delete `_MarkdownPreviewPane` + its state; import new pane; `_FileEditorBody` constructs it with inverted deps)

**Interfaces:**
- Produces:

```dart
class MarkdownPreviewPane extends StatefulWidget {
  const MarkdownPreviewPane({
    required this.controller,
    required this.resolvers,
    required this.codeBlockMode,
    required this.markdownPadding,
    required this.shellColor,
    super.key,
  });
  final CodeLineEditingController controller;   // re-editor
  final MarkdownResolvers resolvers;            // link/image handlers (caller-built)
  final ContentDisplayMode codeBlockMode;
  final EdgeInsetsGeometry markdownPadding;
  final Color shellColor;
}
```

All inherited-context reads move OUT of the pane: `LayoutCubit` select, `WorkbenchEditorOpener`/roots/fs resolver construction, `_FileEditorInsets.markdownPadding`, `_fileEditorShellColor` — supplied by `_FileEditorBody` (which already holds that context). Pane keeps: hover-suppression scroll logic, `ScrollCursorLock`, `AiLineSpacedSelectionStyle`, `SelectionArea`, `MarkdownDisplayModeScope`, `VirtualMarkdownView(flatten: true)`, `_data` tracking + selection-only notify filter.

- [ ] **Step 1: Move the widget**

Cut `_MarkdownPreviewPane` + `_MarkdownPreviewPaneState` (file_editor_surface.dart L558–727) into `markdown_preview_pane.dart` renamed public; convert constructor/state per Interfaces; delete moved private classes from surface; `_FileEditorBody` preview branch becomes:

```dart
        if (mode == MarkdownViewMode.preview) {
          return MarkdownPreviewPane(
            controller: controller,
            resolvers: MarkdownResolvers(
              onLinkTap: (href) {
                unawaited(
                  handleMarkdownPreviewLink(
                    href: href,
                    markdownFilePath: path,
                    workspaceId: workspaceId,
                    workspaceRoots: markdownPreviewWorkspaceRoots(
                      context,
                      workspaceId: workspaceId,
                    ),
                    opener: opener,
                    fs: editor.filesystemFor(workspaceId, path),
                  ),
                );
              },
              resolveImage: (src) => resolveMarkdownPreviewImage(
                src: src,
                markdownFilePath: path,
                workspaceRoots: markdownPreviewWorkspaceRoots(
                  context,
                  workspaceId: workspaceId,
                ),
              ),
            ),
            codeBlockMode: context.select<LayoutCubit, ContentDisplayMode>(
              (c) => c.state.preferences.fileCodeBlockMode,
            ),
            markdownPadding:
                TpWidthValueScope.of<_FileEditorInsets>(context).markdownPadding,
            shellColor: _fileEditorShellColor(Theme.of(context).colorScheme),
          );
        }
```

(`editor`/`opener` locals already exist there.) Keep helpers where used; if `markdownPreviewWorkspaceRoots` resolves twice, hoist to one local `roots` and reuse.

Pane build core (unchanged behavior):

```dart
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.shellColor,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: ValueListenableBuilder<bool>(
          valueListenable: _hoverEffectsEnabled,
          builder: (context, hoverEnabled, child) =>
              ScrollCursorLock(active: !hoverEnabled, child: child!),
          child: SingleChildScrollView(
            padding: widget.markdownPadding,
            child: AiLineSpacedSelectionStyle(
              child: SelectionArea(
                child: MarkdownDisplayModeScope(
                  codeBlockMode: widget.codeBlockMode,
                  child: VirtualMarkdownView(
                    document: compileMarkdown(_data),
                    tokens: buildAppMarkdownTokens(
                      Theme.of(context),
                      MarkdownProfile.document,
                      width: MediaQuery.sizeOf(context).width,
                    ),
                    resolvers: widget.resolvers,
                    flatten: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 2: Verify**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart --tags-exclude integration` (or the suite invocation matching `tool/run_tests.dart` usage — check `--help`).
Expected: clean analyze; suite green (no behavioral change).

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/workbench/markdown_preview_pane.dart \
  client/lib/pages/workbench/file_editor_surface.dart
git commit -m "refactor(editor): extract injectable MarkdownPreviewPane from file_editor_surface"
```

---

### Task 8: MarkdownPreviewFindController (client service)

**Files:**
- Create: `client/lib/services/editor/markdown_preview_find_controller.dart`
- Test: `client/test/services/editor/markdown_preview_find_controller_test.dart`

**Interfaces:**
- Consumes: Task 2/6 package API (`compileMarkdown`, `MarkdownSearchIndex`, `MarkdownSearchHighlightContext`, `kMarkdownSearchMaxHits`).
- Produces:

```dart
const int kMarkdownPreviewFindDebounceMs = 150;

class MarkdownPreviewFindController extends ChangeNotifier {
  MarkdownPreviewFindController();

  bool open;                       // bar visibility (setter notifies)
  void openFind();                 // open = true
  void close();                    // open=false + clear query/hits/error
  void setDocument(MarkdownDocument doc);       // index lifecycle (identity-keyed)
  void search(String value);                    // debounced
  void toggleCaseSensitive();                   // immediate rescan
  void toggleRegex();                           // immediate rescan
  void next(); void previous();                 // wrap-around
  void select(int index);

  String get query;
  bool get caseSensitive;
  bool get regex;
  bool get hasError;               // invalid regex on last attempt
  List<MarkdownSearchHit> get hits;
  int get activeIndex;             // -1 when none
  MarkdownHighlightContext? get highlights;     // null when no hits
  String counterLabel();           // '3/17' | '<cap>+' | '' 
  MarkdownDocument? get document;
}
```

Implementation contract:

- `search('')` clears results immediately (no debounce timer pending).
- Debounce only text input; toggles/setDocument flush synchronously.
- `setDocument` while closed stores doc only; while open with non-empty query → rescan immediately.
- Regex failure: set `hasError=true`, `hits=[]`, `active=-1` (chat precedent: no crash).
- `counterLabel`: hits empty → `''`; capped (`length == kMarkdownSearchMaxHits`) → `'$activeDisplay/${kMarkdownSearchMaxHits}+'`; else `'$activeDisplay/$total'` with `activeDisplay = active + 1`.
- Stale-result guard via monotonically increasing generation checked after synchronous scan completes (scan is synchronous today — generation guards future async).

Skeleton:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tp_markdown/tp_markdown.dart';

const int kMarkdownPreviewFindDebounceMs = 150;

/// Find state for the markdown preview pane...
class MarkdownPreviewFindController extends ChangeNotifier {
  Timer? _debounce;
  MarkdownDocument? _document;
  MarkdownSearchIndex? _index;
  MarkdownSearchIndex? _indexedFor; // identity guard

  String _query = '';
  bool _caseSensitive = false;
  bool _regex = false;
  bool _hasError = false;
  List<MarkdownSearchHit> _hits = const [];
  int _activeIndex = -1;
  bool _open = false;

  bool get open => _open;
  set open(bool value) {
    if (_open == value) return;
    _open = value;
    notifyListeners();
  }

  // ... getters per contract ...

  void openFind() => open = true;

  void close() {
    _debounce?.cancel();
    _debounce = null;
    _query = '';
    _hasError = false;
    _hits = const [];
    _activeIndex = -1;
    if (_open) _open = false;
    notifyListeners();
  }

  void setDocument(MarkdownDocument doc) {
    if (identical(_document, doc)) return;
    _document = doc;
    _index = null;
    _indexedFor = null;
    if (_open && _query.isNotEmpty) {
      _runScan();
    }
  }

  void search(String value) {
    _query = value;
    _debounce?.cancel();
    if (_query.isEmpty) {
      _hasError = false;
      _hits = const [];
      _activeIndex = -1;
      notifyListeners();
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: kMarkdownPreviewFindDebounceMs),
      _runScan,
    );
  }

  void toggleCaseSensitive() {
    _caseSensitive = !_caseSensitive;
    _runScan();
  }

  void toggleRegex() {
    _regex = !_regex;
    _runScan();
  }

  void next() {
    if (_hits.isEmpty) return;
    _activeIndex = (_activeIndex + 1) % _hits.length;
    notifyListeners();
  }

  void previous() {
    if (_hits.isEmpty) return;
    _activeIndex = (_activeIndex - 1 + _hits.length) % _hits.length;
    notifyListeners();
  }

  void select(int index) {
    if (index < 0 || index >= _hits.length) return;
    _activeIndex = index;
    notifyListeners();
  }

  MarkdownHighlightContext? get highlights =>
      _hits.isEmpty || _index == null
          ? null
          : MarkdownSearchHighlightContext.of(_index!, _hits,
              activeOrdinal: _activeIndex);

  String counterLabel() {
    if (_hits.isEmpty) return '';
    final total = _hits.length >= kMarkdownSearchMaxHits
        ? '$kMarkdownSearchMaxHits+'
        : '${_hits.length}';
    final current = _hits.length >= kMarkdownSearchMaxHits
        ? '${_activeIndex + 1}'
        : '${_activeIndex + 1}';
    return '$current/$total';
  }

  void _runScan() {
    final doc = _document;
    if (!_open || doc == null) return;
    _debounce?.cancel();
    _debounce = null;
    final index = _indexFor(doc);
    try {
      final query = MarkdownSearchQuery(
        pattern: _query,
        caseSensitive: _caseSensitive,
        regex: _regex,
      );
      _hits = index.search(query);
      _hasError = false;
    } on MarkdownSearchException {
      _hits = const [];
      _hasError = true;
    }
    _activeIndex = _hits.isEmpty ? -1 : 0;
    notifyListeners();
  }

  MarkdownSearchIndex _indexFor(MarkdownDocument doc) {
    if (!identical(_indexedFor, doc) || _index == null) {
      _index = MarkdownSearchIndex.of(doc);
      _indexedFor = doc;
    }
    return _index!;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 1: Write the failing test FIRST** (before skeleton) using `package:fake_async/fake_async.dart`:

```dart
// client/test/services/editor/markdown_preview_find_controller_test.dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/markdown_preview_find_controller.dart';
import 'package:tp_markdown/tp_markdown.dart';

MarkdownDocument doc() => compileMarkdown('# Title\n\nHello **World** hello\n');

void main() {
  test('debounces text input and scans rendered text', () {
    fakeAsync((async) {
      final c = MarkdownPreviewFindController();
      c.openFind();
      c.setDocument(doc());
      c.search('world');
      expect(c.hits, isEmpty); // not yet flushed
      async.elapse(const Duration(milliseconds: 200));
      expect(c.hits.length, 2); // bold + trailing lowercase (case-insensitive)
      expect(c.activeIndex, 0);
      c.dispose();
    });
  });

  test('empty query clears immediately', () {
    fakeAsync((async) {
      final c = MarkdownPreviewFindController();
      c.openFind();
      c.setDocument(doc());
      c.search('hello');
      async.elapse(const Duration(milliseconds: 200));
      expect(c.hits, isNotEmpty);
      c.search('');
      expect(c.hits, isEmpty);
      c.dispose();
    });
  });

  test('case toggle rescans synchronously', () {
    fakeAsync((async) {
      final c = MarkdownPreviewFindController();
      c.openFind();
      c.setDocument(doc());
      c.search('hello');
      async.elapse(const Duration(milliseconds: 200));
      c.toggleCaseSensitive();
      expect(c.hits.length, 1);
      c.dispose();
    });
  });

  test('invalid regex sets error state instead of throwing', () {
    fakeAsync((async) {
      final c = MarkdownPreviewFindController();
      c.openFind();
      c.setDocument(doc());
      c.toggleRegex();
      c.search('([ ');
      async.elapse(const Duration(milliseconds: 200));
      expect(c.hasError, isTrue);
      expect(c.hits, isEmpty);
      c.dispose();
    });
  });

  test('navigation wraps and clamps', () {
    fakeAsync((async) {
      final c = MarkdownPreviewFindController();
      c.openFind();
      c.setDocument(doc());
      c.search('hello');
      async.elapse(const Duration(milliseconds: 200));
      expect(c.activeIndex, 0);
      c.previous(); // wraps to last
      expect(c.activeIndex, c.hits.length - 1);
      c.next(); // wraps to 0
      expect(c.activeIndex, 0);
      c.select(99);
      expect(c.activeIndex, 0);
      c.dispose();
    });
  });

  test('close resets everything', () {
    fakeAsync((async) {
      final c = MarkdownPreviewFindController();
      c.openFind();
      c.setDocument(doc());
      c.search('hello');
      async.elapse(const Duration(milliseconds: 200));
      c.close();
      expect(c.open, isFalse);
      expect(c.query, isEmpty);
      expect(c.hits, isEmpty);
      c.dispose();
    });
  });

  test('setDocument while open rescans against new content', () {
    fakeAsync((async) {
      final c = MarkdownPreviewFindController();
      c.openFind();
      c.setDocument(doc());
      c.search('title');
      async.elapse(const Duration(milliseconds: 200));
      expect(c.hits, isNotEmpty);
      c.setDocument(compileMarkdown('nothing relevant\n'));
      expect(c.hits, isEmpty);
      c.dispose();
    });
  });
}
```

- [ ] **Step 2: Run to fail, implement skeleton above, run to pass**

Run: `cd client && flutter test test/services/editor/markdown_preview_find_controller_test.dart`
Expected: FAIL → PASS cycle.

- [ ] **Step 3: Commit**

```bash
git add client/lib/services/editor/markdown_preview_find_controller.dart \
  client/test/services/editor/markdown_preview_find_controller_test.dart
git commit -m "feat(editor): debounced markdown preview find controller"
```

---

### Task 9: MarkdownPreviewFindBar widget

**Files:**
- Create: `client/lib/widgets/workbench/markdown_preview_find_bar.dart`
- Test: `client/test/widgets/workbench/markdown_preview_find_bar_test.dart`

**Interfaces:**
- Consumes: Task 8 controller; `widgets/find/find_bar_widgets.dart` primitives; l10n `editorFindHint/editorFindMatchCase/editorFindUseRegex/editorFindPrevious/editorFindNext/editorFindClose/editorFindNoResults`.
- Produces:

```dart
class MarkdownPreviewFindBar extends StatefulWidget {
  const MarkdownPreviewFindBar({required this.controller, super.key});
  final MarkdownPreviewFindController controller;
}
```

Behavior contract:

- Layout mirrors `CodeEditorFindPanel` single-row: `FindBarPanel(width ~420)` → Row `[FindField(width:240, toggles:[caseToggle, regexToggle]), FindCounterText, prevBtn, nextBtn, closeBtn]`.
- Owns `TextEditingController` + `FocusNode(onKeyEvent:)`: Escape→close; Enter→next; Shift+Enter→previous (return `KeyEventResult.handled`, else ignored). Autofocus on mount.
- Field text changes → `controller.search(text)`.
- Counter label: `controller.hasError || hits empty` → l10n.editorFindNoResults with `FindCounterText(empty: true)`; else `controller.counterLabel()`.
- Prev/next disabled when hits empty; close always enabled.
- Listens via `ListenableBuilder(listenable: controller)` AND text-field edits flow one-way (controller → UI only for counter/hit state; field text is source of truth for query input — no feedback loop since controller doesn't rewrite query text).

Test:

```dart
// client/test/widgets/workbench/markdown_preview_find_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/markdown_preview_find_controller.dart';
import 'package:teampilot/widgets/workbench/markdown_preview_find_bar.dart';
import 'package:tp_markdown/tp_markdown.dart';

Future<MarkdownPreviewFindController> pump(WidgetTester tester) async {
  final controller = MarkdownPreviewFindController()
    ..openFind()
    ..setDocument(compileMarkdown('one two three two\n'));
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
    MarkdownPreviewFindBar(controller: controller),
  ]))));
  await tester.pump();
  await tester.enterText(find.byType(TextField), 'two');
  await tester.pump(const Duration(milliseconds: 200));
  return controller;
}

void main() {
  testWidgets('typing populates counter; enter advances', (tester) async {
    final controller = await pump(tester);
    expect(controller.hits.length, 2);
    expect(find.textContaining('1/2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.activeIndex, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(controller.activeIndex, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.open, isFalse);
    expect(controller.hits, isEmpty);
    controller.dispose();
  });

  testWidgets('no-match shows muted No matches', (tester) async {
    final controller = await pump(tester);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(FindCounterText), findsOneWidget);
    controller.dispose();
  });
}
```

(l10n lookup inside widget test needs `MaterialApp(localizationsDelegates: TeampilotLocalizations.delegates, supportedLocales: …)` — copy the delegates setup from an existing widget test, e.g. `grep -rl "localizationsDelegates" client/test | head -3`. Adjust `pump()` accordingly; assertions referencing localized text use `context.l10n.editorFindNoResults` value.)

- [ ] Steps: write test (fail) → implement → pass → commit `feat(editor): markdown preview find bar`.

Implementation notes (exact composition):

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/editor/markdown_preview_find_controller.dart';
import '../find/find_bar_palette.dart';
import '../find/find_bar_widgets.dart';

class MarkdownPreviewFindBar extends StatefulWidget { ... }

class _MarkdownPreviewFindBarState extends State<MarkdownPreviewFindBar> {
  late final TextEditingController _field = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.controller.close();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        widget.controller.previous();
      } else {
        widget.controller.next();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final l10n = context.l10n;
        final noResults = c.hits.isEmpty;
        return FindBarPanel(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FindField(
                  controller: _field,
                  focusNode: _focus,
                  hint: l10n.editorFindHint,
                  autofocus: true,
                  width: 240,
                  onChanged: c.search,
                  toggles: [
                    FindToggleButton(
                      iconAsset: FindBarIcons.caseSensitive,
                      tooltip: l10n.editorFindMatchCase,
                      checked: c.caseSensitive,
                      onTap: c.toggleCaseSensitive,
                    ),
                    FindToggleButton(
                      iconAsset: FindBarIcons.regexp,
                      tooltip: l10n.editorFindUseRegex,
                      checked: c.regex,
                      onTap: c.toggleRegex,
                    ),
                  ],
                ),
                const SizedBox(width: 6),
                FindCounterText(
                  label: noResults ? l10n.editorFindNoResults : c.counterLabel(),
                  empty: noResults,
                ),
                FindActionButton(
                  tooltip: l10n.editorFindPrevious,
                  icon: Icons.keyboard_arrow_up_rounded,
                  enabled: !noResults,
                  onTap: c.previous,
                ),
                FindActionButton(
                  tooltip: l10n.editorFindNext,
                  icon: Icons.keyboard_arrow_down_rounded,
                  enabled: !noResults,
                  onTap: c.next,
                ),
                FindActionButton(
                  tooltip: l10n.editorFindClose,
                  icon: Icons.close_rounded,
                  onTap: c.close,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

Also: opening the bar should seed the field with the previous query — on `didChangeDependencies`/first build if `controller.query.isNotEmpty && _field.text.isEmpty` set text. Keep simple: seed once in initState from controller.query.

---

### Task 10: Wire find into pane + surface toolbar + theme colors

**Files:**
- Modify: `client/lib/pages/workbench/file_editor_surface.dart`
- Modify: `client/lib/pages/workbench/markdown_preview_pane.dart`
- Modify: `client/lib/theme/app_markdown_style_sheet.dart`
- Test: `client/test/pages/workbench/markdown_preview_pane_find_test.dart`

**Interfaces:**
- `MarkdownPreviewPane` gains `final MarkdownPreviewFindController? findController;` (nullable → pane feature-off when null; tests without find keep passing).
- `FileEditorSurface` converts to `StatefulWidget` owning one `MarkdownPreviewFindController` per path (recreate on path change in `didUpdateWidget`, dispose old), passed to `_FileEditorToolbar` (new optional param `findController`) and down through `_FileEditorBody` into the pane.
- Toolbar: inside existing `isMarkdown` branch, when current mode == preview, show `TpIconButton(tooltip: l10n.editorFindHint, icon: Icons.search_rounded, size: TpIconButton.kCompactSize, compact: true, color: iconColor, onTap: findController.openFind)`.
- Theme: `buildAppMarkdownTokens` adds:

```dart
    matchHighlightColor: scheme.primary.withValues(alpha: 0.20),
    matchHighlightActiveColor: scheme.primary.withValues(alpha: 0.45),
```

Pane wiring details:

1. State fields:

```dart
  MarkdownViewController? _viewController;
  MarkdownDocument _document = const MarkdownDocument(blocks: []);
```

2. Compile hoist — initial + on change:

```dart
  late MarkdownDocument _document = compileMarkdown(widget.controller.text);
```
plus in `_onControllerChanged` setState block: `_document = compileMarkdown(next);` and in `didUpdateWidget` controller-swap branch likewise.

3. Find binding effect — whenever `widget.findController`/`_document` changes, push doc:

```dart
  void _syncFindDocument() {
    widget.findController?.setDocument(_document);
  }
```
call from initState (post-initial-compile), `_onControllerChanged`, `didUpdateWidget`.

4. View controller lifecycle: create lazily in `initState` (`_viewController = MarkdownViewController();` dispose in dispose). Reveal listener — drive reveal on active-hit change:

```dart
  void _onFindChanged() {
    final find = widget.findController;
    if (find == null) return;
    setState(() {}); // repaint highlights
    final index = find.activeIndex;
    if (index >= 0 && index < find.hits.length && mounted) {
      final hit = find.hits[index];
      final containers = find.document == null
          ? const <MarkdownSearchContainer>[]
          : MarkdownSearchIndex.of(find.document!).containers; // NO — cache!
```

Cache containers: pane keeps `MarkdownSearchIndex? _findIndex` updated inside `_syncFindDocument` via `MarkdownSearchIndex.of` stored alongside; expose from controller instead — ADD to Task 8 controller: `MarkdownSearchContainer? containerOf(MarkdownSearchHit hit)` returning `index.containers[hit.container]` (bounds-checked). Use it here:

```dart
      final container = find.containerOf(hit);
      if (container != null) {
        unawaited(_viewController?.revealBlock(container.blockIndex));
      }
    }
  }
```
subscribe in initState (`find.addListener(_onFindChanged)`), swap/dispose in didUpdateWidget/dispose. Remove the bare `setState((){})` duplication: highlight repaint flows through the same listener.

5. Build — Stack overlay + context threading:

```dart
    final highlights = find?.highlights;
    // ... existing tree, VirtualMarkdownView gains:
                    controller: _viewController,
                    highlights: highlights,
    // Wrap the whole ColoredBox in:
    return ShortcutFocus(
      claims: {KeyChord(key: 'f', mods: [KeyChordMod.mod])},
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.keyF, control: true): _OpenFindIntent(),
          SingleActivator(LogicalKeyboardKey.keyF, meta: true): _OpenFindIntent(),
        },
        child: Actions(
          actions: {
            _OpenFindIntent: CallbackAction<_OpenFindIntent>(
              onInvoke: (_) {
                find?.openFind();
                return null;
              },
            ),
          },
          child: Stack(children: [
            Positioned.fill(child: existingColoredBoxTree),
            if (find?.open ?? false)
              Positioned(
                top: 8,
                right: 16,
                child: MarkdownPreviewFindBar(controller: find!),
              ),
          ]),
        ),
      ),
    );
```

with `class _OpenFindIntent extends Intent { const _OpenFindIntent(); }` (private to pane file). Imports add `../../services/commands/key_chord.dart` + `shortcut_focus.dart` + `../../services/editor/markdown_preview_find_controller.dart` + `../../../widgets/workbench/markdown_preview_find_bar.dart` (paths relative to `pages/workbench/` — verify with analyzer).

Integration test:

```dart
// client/test/pages/workbench/markdown_preview_pane_find_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:teampilot/pages/workbench/markdown_preview_pane.dart';
import 'package:teampilot/services/editor/markdown_preview_find_controller.dart';
import 'package:tp_markdown/tp_markdown.dart';

void main() {
  testWidgets('Mod+F opens bar; typing paints highlight; esc closes',
      (tester) async {
    final editing = CodeLineEditingController.fromText('# Hi\n\nfindme here\n');
    final find = MarkdownPreviewFindController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MarkdownPreviewPane(
          controller: editing,
          resolvers: const MarkdownResolvers(),
          codeBlockMode: ContentDisplayMode.flatten,
          markdownPadding: const EdgeInsets.all(24),
          shellColor: Colors.white,
          findController: find,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Open via Mod+F shortcut
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byType(MarkdownPreviewFindBar), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'findme');
    await tester.pump(const Duration(milliseconds: 250));

    final wash = buildAppMarkdownTokens(
      Theme.of(tester.element(find.byType(Scaffold))),
      MarkdownProfile.document,
      width: 800,
    ).matchHighlightColor;
    bool washed(InlineSpan s) => s is TextSpan &&
        s.style?.backgroundColor == wash ||
        (s.children ?? []).any(washed);
    final highlighted = tester
        .widgetList<Text>(find.byType(Text))
        .any((t) => t.textSpan != null && washed(t.textSpan!));
    expect(highlighted, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(MarkdownPreviewFindBar), findsNothing);
    find.dispose();
    editing.dispose();
  });
}
```

(l10n delegates needed for the bar labels — same fix-up as Task 9 test.)

- [ ] Steps: theme colors + controller.containerOf addition (+ its unit test tweak) → pane/surface wiring → integration test red→green → `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` clean → commit `feat(editor): wire find into markdown preview (Mod+F, highlight, navigation)`.

---

### Task 11: Full verification

- [ ] **Step 1:** `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` — zero issues.
- [ ] **Step 2:** `cd client && dart run tool/run_tests.dart` — full suite green.
- [ ] **Step 3:** Manual smoke (desktop run): open a large `.md`, Mod+F, type, navigate n/N, toggle Aa/.*, Esc; verify masked huge code blocks auto-expand when containing matches; verify floating preview tab also works.
- [ ] **Step 4:** Commit any remaining fixes: `fix(editor): markdown preview search polish`.

---

## Self-Review Checklist (completed during plan authoring)

- Spec coverage: search semantics/index (Tasks 2), highlight injection (Tasks 1/3/4), reveal (Task 5), exports (Task 6), controller/bar/wiring/theme/l10n (Tasks 7–10), caps/debounce/error handling (Task 8/9), masked-code auto-expand (Task 3 code-block section), second-pass correction (Task 5), tests per layer (each task).
- Deviation logged vs spec: image alt text excluded from search (spec updated inline); invalid regex renders as "no matches" state rather than a distinct message (uses existing `editorFindNoResults`).
- Type consistency: `containerOf(hit)` produced by Task 8, consumed by Task 10; path-step types defined once (Task 1) reused everywhere.
