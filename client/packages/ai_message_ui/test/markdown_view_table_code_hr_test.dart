import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('table cells use tableCellsPadding from tokens', (tester) async {
    const padding = EdgeInsets.symmetric(horizontal: 20, vertical: 10);
    final tokens = MarkdownTokens.test(tableCellsPadding: padding);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: const MarkdownDocument(
              blocks: [
                TableBlock(
                  headers: [
                    InlineDocument(runs: [TextRun('H1')]),
                    InlineDocument(runs: [TextRun('H2')]),
                  ],
                  rows: [
                    [
                      InlineDocument(runs: [TextRun('A')]),
                      InlineDocument(runs: [TextRun('B')]),
                    ],
                  ],
                ),
              ],
            ),
            tokens: tokens,
          ),
        ),
      ),
    );

    final cellPaddings = tester
        .widgetList<Padding>(find.byType(Padding))
        .where((p) => p.padding == padding)
        .length;
    expect(cellPaddings, greaterThanOrEqualTo(2));
  });

  testWidgets('table head row uses tableHeadBackground from tokens', (tester) async {
    const headColor = Color(0xFFFF0000);
    final tokens = MarkdownTokens.test(tableHeadBackground: headColor);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: const MarkdownDocument(
              blocks: [
                TableBlock(
                  headers: [InlineDocument(runs: [TextRun('Name')])],
                  rows: [
                    [InlineDocument(runs: [TextRun('Alice')])],
                  ],
                ),
              ],
            ),
            tokens: tokens,
          ),
        ),
      ),
    );

    final headBoxes = tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .where((box) => box.color == headColor);
    expect(headBoxes, isNotEmpty);
  });

  testWidgets('table shows bold cell text without Flutter Table', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: const MarkdownDocument(
              blocks: [
                TableBlock(
                  headers: [
                    InlineDocument(runs: [TextRun('A')]),
                    InlineDocument(runs: [TextRun('B')]),
                  ],
                  rows: [
                    [
                      InlineDocument(runs: [TextRun('x')]),
                      InlineDocument(
                        runs: [
                          StrongRun(children: [TextRun('bold-cell')]),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
            tokens: MarkdownTokens.test(),
          ),
        ),
      ),
    );

    expect(find.byType(Table), findsNothing);
    expect(find.textContaining('bold-cell'), findsOneWidget);

    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    final boldSpan = richTexts
        .expand((r) => _flattenSpans(r.text))
        .whereType<TextSpan>()
        .firstWhere((s) => s.text == 'bold-cell');
    expect(boldSpan.style?.fontWeight, FontWeight.w700);
  });

  testWidgets('code block shows language label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: const MarkdownDocument(
              blocks: [
                CodeBlock(language: 'dart', text: 'void main() {}'),
              ],
            ),
            tokens: MarkdownTokens.test(),
          ),
        ),
      ),
    );

    expect(find.text('dart'), findsOneWidget);
    expect(find.text('void main() {}'), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
  });

  testWidgets('horizontal rule renders Divider not placeholder', (tester) async {
    final tokens = MarkdownTokens.test();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: const MarkdownDocument(
              blocks: [HorizontalRuleBlock()],
            ),
            tokens: tokens,
          ),
        ),
      ),
    );

    final divider = tester.widget<Divider>(find.byType(Divider));
    expect(divider.color, tokens.borderColor);
    expect(find.text('HorizontalRuleBlock'), findsNothing);
  });
}

Iterable<InlineSpan> _flattenSpans(InlineSpan span) sync* {
  yield span;
  if (span is TextSpan && span.children != null) {
    for (final child in span.children!) {
      yield* _flattenSpans(child);
    }
  }
}
