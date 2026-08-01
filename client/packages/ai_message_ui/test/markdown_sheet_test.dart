import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:ai_message_ui/src/markdown/compiled_text_part_view.dart';
import 'package:ai_message_ui/src/markdown/ir/markdown_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CompiledTextPartView table uses style table chrome', (tester) async {
    const padding = EdgeInsets.symmetric(horizontal: 14, vertical: 8);
    const head = Color(0x14000000);
    final base = MarkdownTokens.test();
    final tokens = MarkdownTokens(
      body: base.body,
      h1: base.h1,
      h2: base.h2,
      h3: base.h3,
      h4: base.h4,
      h5: base.h5,
      h6: base.h6,
      link: base.link,
      inlineCode: base.inlineCode,
      codeBlock: base.codeBlock,
      codeLanguage: base.codeLanguage,
      listBullet: base.listBullet,
      blockquote: base.blockquote,
      tableHead: base.tableHead,
      tableBody: base.tableBody,
      mutedSurface: base.mutedSurface,
      borderColor: base.borderColor,
      codeBlockRadius: base.codeBlockRadius,
      tableCellsPadding: padding,
      tableHeadBackground: head,
      tableBodyBackground: Colors.transparent,
      headingBottom: base.headingBottom,
      paragraphGap: base.paragraphGap,
      blockGap: base.blockGap,
      listItemGap: base.listItemGap,
      listIndent: base.listIndent,
      ruleGap: base.ruleGap,
      h1TopSpacing: base.h1TopSpacing,
      h2TopSpacing: base.h2TopSpacing,
      h3TopSpacing: base.h3TopSpacing,
      h4TopSpacing: base.h4TopSpacing,
      h5TopSpacing: base.h5TopSpacing,
      h6TopSpacing: base.h6TopSpacing,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompiledTextPartView(
            style: tokens,
            document: const MarkdownDocument(
              blocks: [
                TableBlock(
                  headers: [
                    InlineDocument(runs: [TextRun('Doc')]),
                  ],
                  rows: [
                    [
                      InlineDocument(runs: [TextRun('AGENTS.md')]),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final headerPad = tester.widgetList<Padding>(find.byType(Padding)).where(
      (p) => p.padding == padding,
    );
    expect(headerPad, isNotEmpty);

    final fills = tester.widgetList<ColoredBox>(find.byType(ColoredBox));
    expect(fills.any((c) => c.color == head), isTrue);
  });

  testWidgets(
    'AiTextPartView uses compiled path for GFM table and onTapLink',
    (tester) async {
      String? tappedHref;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AiMessageTheme.test()]),
          home: Scaffold(
            body: AiTextPartView(
              text:
                  '| A | B |\n| --- | --- |\n| 1 | 2 |\n\n[link](https://example.com)',
              onTapLink: (text, href, title) {
                tappedHref = href;
              },
            ),
          ),
        ),
      );

      expect(find.byType(CompiledTextPartView), findsOneWidget);
      expect(find.textContaining('1'), findsOneWidget);
      await tester.tap(find.text('link'));
      await tester.pump();
      expect(tappedHref, 'https://example.com');
    },
  );
}
