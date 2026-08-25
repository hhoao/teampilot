// VirtualMarkdownView must thread highlight context into its mounted units:
// merged paragraph runs resolve per-paragraph container highlights.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/src/render/highlight_context.dart';
import 'package:tp_markdown/tp_markdown.dart';

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
    final ctx = _Ctx({
      30: MarkdownContainerHighlights(ranges: [
        const TextRange(start: 7, end: 12),
      ]),
    });

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

    bool hasWash(InlineSpan s) {
      if (s is! TextSpan) return false;
      return s.style?.backgroundColor == wash ||
          (s.children ?? const <InlineSpan>[]).any(hasWash);
    }

    // Deterministic whole-document scan: step through the parent scroll
    // instead of trusting one estimate-dependent jump offset.
    var found = false;
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    for (var offset = 0.0;
        offset <= position.maxScrollExtent && !found;
        offset += 300) {
      position.jumpTo(offset);
      await tester.pumpAndSettle();
      found = tester.widgetList<Text>(find.byType(Text)).any((t) =>
          t.textSpan != null &&
          _flat(t.textSpan!).contains('needle') &&
          hasWash(t.textSpan!));
    }
    expect(found, isTrue);
  });
}
