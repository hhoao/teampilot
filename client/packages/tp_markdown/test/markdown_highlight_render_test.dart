// Render-level highlight threading tests: match washes must reach paragraph,
// heading, list-item, table-cell, and code-block text via container paths.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';
import 'package:tp_markdown/src/render/highlight_context.dart';

MarkdownContainerHighlights _hl({
  required List<TextRange> ranges,
  TextRange? active,
}) =>
    MarkdownContainerHighlights(ranges: ranges, active: active);

class _Ctx implements MarkdownHighlightContext {
  _Ctx(this.map);

  final Map<int, MarkdownContainerHighlights> map;

  @override
  MarkdownContainerHighlights? forContainer(
    int blockIndex,
    List<MarkdownPathStep> path,
  ) =>
      map[blockIndex];
}

List<Text> _richParagraphTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .where((t) => t.textSpan != null)
    .toList();

String _spanText(InlineSpan span) {
  if (span is TextSpan) {
    return (span.text ?? '') + (span.children ?? []).map(_spanText).join();
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
    bool walk(InlineSpan s) => hasWashedBold(s) ||
        (s is TextSpan && (s.children ?? const <InlineSpan>[]).any(walk));
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

  testWidgets('null context renders identically (no wash spans)',
      (tester) async {
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
