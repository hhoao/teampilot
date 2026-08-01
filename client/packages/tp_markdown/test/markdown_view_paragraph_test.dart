import 'package:tp_markdown/tp_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _textSpanPlainText(InlineSpan span) {
  if (span is TextSpan) {
    if (span.text != null) return span.text!;
    return (span.children ?? [])
        .map(_textSpanPlainText)
        .join();
  }
  return '';
}

bool _richTextContains(Text widget, String needle) {
  final span = widget.textSpan;
  if (span == null) return false;
  return _textSpanPlainText(span).contains(needle);
}

void main() {
  testWidgets('consecutive paragraphs merge into one Text.rich', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: const MarkdownDocument(
              blocks: [
                ParagraphBlock(runs: [TextRun('First paragraph')]),
                ParagraphBlock(runs: [TextRun('Second paragraph')]),
              ],
            ),
            tokens: MarkdownTokens.test(),
          ),
        ),
      ),
    );

    final richTexts = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.textSpan != null)
        .toList();
    expect(richTexts, hasLength(1));
    expect(_richTextContains(richTexts.single, 'First paragraph'), isTrue);
    expect(_richTextContains(richTexts.single, 'Second paragraph'), isTrue);
  });

  testWidgets('heading between paragraphs stays separate', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: const MarkdownDocument(
              blocks: [
                ParagraphBlock(runs: [TextRun('Intro')]),
                HeadingBlock(level: 2, runs: [TextRun('Title')]),
                ParagraphBlock(runs: [TextRun('More')]),
              ],
            ),
            tokens: MarkdownTokens.test(),
          ),
        ),
      ),
    );

    final richTexts = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.textSpan != null)
        .toList();
    expect(richTexts, hasLength(3));

    final intro = richTexts.firstWhere((t) => _richTextContains(t, 'Intro'));
    expect(_richTextContains(intro, 'Title'), isFalse);
    expect(_richTextContains(intro, 'More'), isFalse);

    final heading = richTexts.firstWhere((t) => _richTextContains(t, 'Title'));
    expect(_richTextContains(heading, 'Intro'), isFalse);
    expect(_richTextContains(heading, 'More'), isFalse);
  });

  testWidgets('merged paragraphs skip paragraphGap SizedBox', (tester) async {
    const paragraphGap = 17.0;
    final tokens = MarkdownTokens.test(paragraphGap: paragraphGap);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: const MarkdownDocument(
              blocks: [
                ParagraphBlock(runs: [TextRun('One')]),
                ParagraphBlock(runs: [TextRun('Two')]),
              ],
            ),
            tokens: tokens,
          ),
        ),
      ),
    );

    final sizedBoxHeights = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .map((s) => s.height)
        .whereType<double>()
        .toList();
    expect(sizedBoxHeights, isNot(contains(paragraphGap)));

    final richTexts = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.textSpan != null)
        .toList();
    expect(richTexts, hasLength(1));
    final root = richTexts.single.textSpan! as TextSpan;
    final children = root.children ?? const <InlineSpan>[];
    final blankLine = children.firstWhere(
      (span) => span is TextSpan && span.text == '\n\n',
    ) as TextSpan;
    final fontSize = tokens.body.fontSize ?? 14.0;
    expect(blankLine.style?.height, closeTo(paragraphGap / fontSize, 0.001));
  });

  testWidgets('paragraph then code uses blockGap SizedBox', (tester) async {
    const blockGap = 22.0;
    final tokens = MarkdownTokens.test(blockGap: blockGap);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: const MarkdownDocument(
              blocks: [
                ParagraphBlock(runs: [TextRun('Body')]),
                CodeBlock(text: 'fn main() {}'),
              ],
            ),
            tokens: tokens,
          ),
        ),
      ),
    );

    final sizedBoxHeights = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .map((s) => s.height)
        .whereType<double>()
        .toList();
    expect(sizedBoxHeights, contains(blockGap));
  });

  testWidgets('heading uses token heading style in Text.rich', (tester) async {
    final tokens = MarkdownTokens.test();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: const MarkdownDocument(
              blocks: [
                HeadingBlock(level: 2, runs: [TextRun('Section')]),
              ],
            ),
            tokens: tokens,
          ),
        ),
      ),
    );

    final richTexts = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.textSpan != null)
        .toList();
    expect(richTexts, hasLength(1));
    expect(richTexts.single.textSpan?.style?.fontSize, tokens.h2.fontSize);
  });

  testWidgets('link tap calls onLinkTap resolver', (tester) async {
    String? tappedHref;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: const MarkdownDocument(
              blocks: [
                ParagraphBlock(
                  runs: [
                    TextRun('See '),
                    LinkRun(
                      url: 'https://example.com',
                      children: [TextRun('docs')],
                    ),
                    TextRun('.'),
                  ],
                ),
              ],
            ),
            tokens: MarkdownTokens.test(),
            resolvers: MarkdownResolvers(
              onLinkTap: (href) => tappedHref = href,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.textContaining('docs'));
    await tester.pump();
    expect(tappedHref, 'https://example.com');
  });
}
