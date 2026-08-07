import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

/// Align hands the child loose constraints (like a Column does in the real
/// chat tree) so `VirtualMarkdownView.maxHeight` takes effect — a tight
/// SizedBox would clamp `maxHeight` back up to its own size (BoxConstraints
/// enforce semantics).
Widget _harness(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 300,
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
}

/// Alternating paragraph/heading keeps each block its own virtualized unit
/// (consecutive paragraphs would merge into a single run/unit).
MarkdownDocument _blockDoc(int count) {
  return MarkdownDocument(
    blocks: [
      for (var i = 0; i < count; i++)
        if (i.isEven)
          ParagraphBlock(runs: [TextRun('block-$i')])
        else
          HeadingBlock(level: 3, runs: [TextRun('block-$i')]),
    ],
  );
}

Finder _blockText(String needle) =>
    find.textContaining(needle, findRichText: true);

void main() {
  testWidgets('only visible blocks are built; scrolling reaches the tail', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        VirtualMarkdownView(
          document: _blockDoc(200),
          tokens: MarkdownTokens.test(),
          maxHeight: 300,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Head mounted, far tail not built at all.
    expect(_blockText('block-0'), findsOneWidget);
    expect(_blockText('block-190'), findsNothing);

    // Scroll to bottom: tail mounts, head recycles out.
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(_blockText('block-199'), findsOneWidget);
    expect(_blockText('block-0'), findsNothing);
  });

  testWidgets('viewport height is capped by maxHeight', (tester) async {
    await tester.pumpWidget(
      _harness(
        VirtualMarkdownView(
          document: _blockDoc(50),
          tokens: MarkdownTokens.test(),
          maxHeight: 120,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(SingleChildScrollView).first).height,
      120,
    );
  });

  testWidgets('flatten renders natural height and only mounts visible blocks', (
    tester,
  ) async {
    // Parent scroll: the flatten view must size naturally and follow THIS scroll.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: SingleChildScrollView(
              child: VirtualMarkdownView(
                document: _blockDoc(200),
                tokens: MarkdownTokens.test(),
                flatten: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Natural height: as tall as all 200 blocks, not bounded to the viewport.
    expect(
      tester.getSize(find.byType(VirtualMarkdownView)).height,
      greaterThan(1000),
    );
    // Only visible blocks mounted; far tail not built.
    expect(_blockText('block-0'), findsOneWidget);
    expect(_blockText('block-190'), findsNothing);

    // Scrolling the PARENT reaches the tail.
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(_blockText('block-199'), findsOneWidget);
  });

  testWidgets('link tap routes through resolvers', (tester) async {
    String? tapped;
    final doc = MarkdownDocument(
      blocks: [
        ParagraphBlock(
          runs: [LinkRun(url: 'https://x.test', children: [TextRun('go')])],
        ),
      ],
    );
    await tester.pumpWidget(
      _harness(
        VirtualMarkdownView(
          document: doc,
          tokens: MarkdownTokens.test(),
          resolvers: MarkdownResolvers(onLinkTap: (href) => tapped = href),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('go'));
    await tester.pump();

    expect(tapped, 'https://x.test');
  });
}
