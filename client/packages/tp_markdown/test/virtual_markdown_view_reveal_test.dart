import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

/// Alternating paragraph/heading keeps each block its own virtualized unit
/// (consecutive paragraphs would merge into one run/unit, collapsing every
/// block index onto unit 0).
MarkdownDocument tallDoc(int n) => MarkdownDocument(blocks: [
      for (var i = 0; i < n; i++)
        if (i.isEven)
          ParagraphBlock(runs: [TextRun('block $i ${'filler text ' * 20}')])
        else
          HeadingBlock(level: 3, runs: [TextRun('block $i')]),
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
