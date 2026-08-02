import 'package:tp_markdown/tp_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('heading then list gap uses collapsed margins', (tester) async {
    final tokens = MarkdownTokens.test(
      h2Margin: const EdgeInsets.only(top: 36, bottom: 8),
      listMargin: const EdgeInsets.only(bottom: 28),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: MarkdownDocument(
              blocks: [
                const HeadingBlock(
                  level: 2,
                  runs: [TextRun('Acknowledgements')],
                ),
                ListBlock(
                  ordered: false,
                  items: [
                    ContentListItem(runs: [const TextRun('File icons')]),
                  ],
                ),
              ],
            ),
            tokens: tokens,
          ),
        ),
      ),
    );
    final heights = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .map((s) => s.height)
        .whereType<double>()
        .toList();
    expect(heights, contains(8));
    expect(heights, isNot(contains(28)));
  });
}
