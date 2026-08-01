import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('heading then list gap is headingBottom not blockGap', (tester) async {
    final tokens = MarkdownTokens.test(
      headingBottom: 8,
      blockGap: 28,
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
    expect(heights, contains(tokens.headingBottom));
    expect(heights, isNot(contains(tokens.blockGap)));
  });
}
