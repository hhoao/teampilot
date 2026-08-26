import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/src/ir/markdown_document.dart';
import 'package:tp_markdown/src/search/markdown_search_index.dart';

void main() {
  MarkdownDocument doc() => const MarkdownDocument(
    blocks: [
      ParagraphBlock(
        runs: [
          TextRun('Hello '),
          StrongRun(children: [TextRun('World')]),
          TextRun(' again'),
        ],
      ),
      HeadingBlock(level: 2, runs: [TextRun('World Title')]),
      CodeBlock(language: 'dart', text: 'final world = 1;\n'),
      BlockquoteBlock(
        blocks: [
          ParagraphBlock(runs: [TextRun('quoted world')]),
        ],
      ),
      ListBlock(
        ordered: false,
        items: [
          ContentListItem(runs: [TextRun('item world one')]),
        ],
      ),
      TableBlock(
        headers: [
          InlineDocument(runs: [TextRun('Col World')]),
        ],
        rows: [
          [
            InlineDocument(runs: [TextRun('cell world')]),
          ],
        ],
      ),
    ],
  );

  group('projection', () {
    final index = MarkdownSearchIndex.of(doc());
    test('enumerates containers in document order incl. nesting', () {
      final kinds = index.containers
          .map(
            (c) => (
              c.blockIndex,
              c.path.map((s) => s.runtimeType.toString()).join('>'),
            ),
          )
          .toList();
      expect(kinds, [
        (0, ''),
        (1, ''),
        (2, ''),
        (3, 'ChildStep'),
        (4, 'ListItemStep'),
        (5, 'TableHeaderStep'),
        (5, 'TableCellStep'),
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
      // paragraph, heading, code, quote, list item, header cell, body cell
      expect(hits, hasLength(7));
      expect(hits.first.container, 0);
      expect(hits.first.start, 6);
      expect(hits.first.end, 11);
    });

    test('case sensitive filters', () {
      final hits = index.search(
        const MarkdownSearchQuery(pattern: 'World', caseSensitive: true),
      );
      expect(hits, hasLength(3)); // paragraph bold + heading + header cell
    });

    test('regex works and skips zero-length matches', () {
      final hits = index.search(
        const MarkdownSearchQuery(pattern: r'w(orl)d', regex: true),
      );
      expect(hits, hasLength(7));
      expect(hits.first.end - hits.first.start, 5);
      final empty = index.search(
        const MarkdownSearchQuery(pattern: r'x*', regex: true),
      );
      expect(empty, isEmpty);
    });

    test('invalid regex throws MarkdownSearchException', () {
      expect(
        () =>
            index.search(const MarkdownSearchQuery(pattern: '([', regex: true)),
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
      final hl = ctx.forContainer(c.blockIndex, c.path)!;
      expect(hl.active, TextRange(start: hits[1].start, end: hits[1].end));
      expect(ctx.forContainer(99, const []), isNull);
    });

    test('hit cap stops scanning at exactly kMarkdownSearchMaxHits', () {
      final occurrences = kMarkdownSearchMaxHits + 500;
      final repetitive = MarkdownDocument(
        blocks: [
          ParagraphBlock(runs: [TextRun('a ' * occurrences)]),
          ParagraphBlock(runs: [TextRun('tail a')]),
        ],
      );
      final idx = MarkdownSearchIndex.of(repetitive);
      final hits = idx.search(const MarkdownSearchQuery(pattern: 'a'));
      expect(hits, hasLength(kMarkdownSearchMaxHits));
      // Cap stops scanning: the tail container's match never lands.
      expect(hits.last.container, 0);
    });

    test('case folding keeps offsets on the original string', () {
      // 'İ'.toLowerCase() is two code units ('i' + combining dot), so a
      // fold-then-indexOf scan would misalign every offset after it.
      const dotted = MarkdownDocument(
        blocks: [
          ParagraphBlock(runs: [TextRun('İa b')]),
        ],
      );
      final idx = MarkdownSearchIndex.of(dotted);
      final hits = idx.search(const MarkdownSearchQuery(pattern: 'a'));
      expect(hits, hasLength(1));
      expect(hits.single.start, 1); // position of 'a' in 'İa b'
      expect('İa b'.substring(hits.single.start, hits.single.end), 'a');
    });
  });
}
