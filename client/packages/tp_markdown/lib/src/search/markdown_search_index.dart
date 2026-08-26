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

void _addRuns(
  List<MarkdownSearchContainer> containers,
  List<InlineRun> runs,
  int blockIndex,
  List<MarkdownPathStep> path,
) {
  final text = inlineTextPieces(runs).map((p) => p.text).join();
  if (text.isEmpty) return;
  containers.add(
    MarkdownSearchContainer(
      blockIndex: blockIndex,
      path: List.unmodifiable(path),
      plainText: text,
    ),
  );
}

void _visitNested(
  List<MarkdownSearchContainer> containers,
  List<MarkdownBlock> blocks,
  int blockIndex,
  List<MarkdownPathStep> basePath,
) {
  for (var c = 0; c < blocks.length; c++) {
    _visitBlock(containers, blocks[c], blockIndex, [...basePath, ChildStep(c)]);
  }
}

void _visitList(
  List<MarkdownSearchContainer> containers,
  ListBlock block,
  int blockIndex,
  List<MarkdownPathStep> basePath,
) {
  for (var i = 0; i < block.items.length; i++) {
    final item = block.items[i];
    final itemPath = [...basePath, ListItemStep(i)];
    _addRuns(containers, item.runs, blockIndex, itemPath);
    _visitNested(containers, item.children, blockIndex, itemPath);
  }
}

void _visitBlock(
  List<MarkdownSearchContainer> containers,
  MarkdownBlock block,
  int blockIndex,
  List<MarkdownPathStep> basePath,
) {
  switch (block) {
    case ParagraphBlock(:final runs):
      _addRuns(containers, runs, blockIndex, basePath);
    case HeadingBlock(:final runs):
      _addRuns(containers, runs, blockIndex, basePath);
    case ListBlock():
      _visitList(containers, block, blockIndex, basePath);
    case BlockquoteBlock(:final blocks):
      _visitNested(containers, blocks, blockIndex, basePath);
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
        _addRuns(containers, headers[c].runs, blockIndex, [
          ...basePath,
          TableHeaderStep(c),
        ]);
      }
      for (var r = 0; r < rows.length; r++) {
        for (var c = 0; c < rows[r].length; c++) {
          _addRuns(containers, rows[r][c].runs, blockIndex, [
            ...basePath,
            TableCellStep(r, c),
          ]);
        }
      }
    case ImageBlock() || RawLiteralBlock() || HorizontalRuleBlock():
      break;
  }
}

/// Document-level search: projects the IR into ordered containers once, scans
/// their plain text per query.
class MarkdownSearchIndex {
  factory MarkdownSearchIndex.of(MarkdownDocument document) {
    final containers = <MarkdownSearchContainer>[];
    final blocks = document.blocks;
    for (var i = 0; i < blocks.length; i++) {
      _visitBlock(containers, blocks[i], i, const []);
    }
    return MarkdownSearchIndex._(containers);
  }

  MarkdownSearchIndex._(this.containers);

  final List<MarkdownSearchContainer> containers;

  /// Scans every container in order; literal queries run an escaped
  /// case-aware [RegExp] over the original text (manual `toLowerCase()` can
  /// change string length for rare Unicode — e.g. `İ` folds to two code units
  /// — which would shift highlight offsets), regex queries use the pattern as
  /// given. Both go through [RegExp.allMatches], skipping zero-length matches.
  /// Throws [MarkdownSearchException] when a regex pattern cannot compile.
  List<MarkdownSearchHit> search(MarkdownSearchQuery query) {
    if (query.pattern.isEmpty) return const [];
    final RegExp re;
    try {
      re = RegExp(
        query.regex ? query.pattern : RegExp.escape(query.pattern),
        caseSensitive: query.caseSensitive,
      );
    } on FormatException catch (e) {
      throw MarkdownSearchException(e.message);
    }
    return _collect((text) {
      return re.allMatches(text).map((m) => (m.start, m.end));
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

  /// Highlight context resolving [hits]; the hit at [activeOrdinal] paints as
  /// the active match (-1 = none).
  MarkdownSearchHighlightContext highlightsFor(
    List<MarkdownSearchHit> hits, {
    int activeOrdinal = -1,
  }) => MarkdownSearchHighlightContext.of(
    this,
    hits,
    activeOrdinal: activeOrdinal,
  );
}

/// [MarkdownHighlightContext] resolved from an index + hit list.
class MarkdownSearchHighlightContext implements MarkdownHighlightContext {
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

  MarkdownSearchHighlightContext._(this._entries);

  final Map<String, MarkdownContainerHighlights> _entries;

  @override
  MarkdownContainerHighlights? forContainer(
    int blockIndex,
    List<MarkdownPathStep> path,
  ) => _entries[encodeAddress(blockIndex, path)];

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
