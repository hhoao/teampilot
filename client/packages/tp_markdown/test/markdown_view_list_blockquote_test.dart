import 'package:tp_markdown/tp_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('list items separated by listItemGap', (tester) async {
    const listItemGap = 9.0;
    final tokens = MarkdownTokens.test(listItemGap: listItemGap);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: const MarkdownDocument(
              blocks: [
                ListBlock(
                  ordered: false,
                  items: [
                    ContentListItem(runs: [TextRun('First')]),
                    ContentListItem(runs: [TextRun('Second')]),
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
    expect(heights, contains(listItemGap));
  });

  testWidgets('nested blockquote renders child text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: const MarkdownDocument(
              blocks: [
                BlockquoteBlock(
                  blocks: [
                    ParagraphBlock(runs: [TextRun('Quoted wisdom')]),
                  ],
                ),
              ],
            ),
            tokens: MarkdownTokens.test(),
          ),
        ),
      ),
    );

    expect(find.textContaining('Quoted wisdom'), findsOneWidget);
    expect(find.text('BlockquoteBlock'), findsNothing);
  });

  testWidgets('ordered list uses numeric markers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: const MarkdownDocument(
              blocks: [
                ListBlock(
                  ordered: true,
                  items: [
                    ContentListItem(runs: [TextRun('Alpha')]),
                    ContentListItem(runs: [TextRun('Beta')]),
                  ],
                ),
              ],
            ),
            tokens: MarkdownTokens.test(),
          ),
        ),
      ),
    );

    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
  });

  testWidgets('task list uses checkbox markers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: const MarkdownDocument(
              blocks: [
                ListBlock(
                  ordered: false,
                  items: [
                    ContentListItem(
                      runs: [TextRun('Done')],
                      isTaskChecked: true,
                    ),
                    ContentListItem(
                      runs: [TextRun('Todo')],
                      isTaskChecked: false,
                    ),
                  ],
                ),
              ],
            ),
            tokens: MarkdownTokens.test(),
          ),
        ),
      ),
    );

    expect(find.text('☑'), findsOneWidget);
    expect(find.text('☐'), findsOneWidget);
  });
}
