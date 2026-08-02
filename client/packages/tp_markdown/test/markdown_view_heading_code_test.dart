import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

void main() {
  testWidgets(
    'inline code inside heading keeps heading fontSize with mono family',
    (tester) async {
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
        inlineCode: base.body.copyWith(
          fontFamily: 'Mono',
          fontSize: base.body.fontSize,
          backgroundColor: base.inlineCode.backgroundColor,
        ),
        codeBlock: base.codeBlock,
        codeLanguage: base.codeLanguage,
        listBullet: base.listBullet,
        blockquote: base.blockquote,
        tableHead: base.tableHead,
        tableBody: base.tableBody,
        mutedSurface: base.mutedSurface,
        borderColor: base.borderColor,
        codeBlockRadius: base.codeBlockRadius,
        tableCellsPadding: base.tableCellsPadding,
        tableHeadBackground: base.tableHeadBackground,
        tableBodyBackground: base.tableBodyBackground,
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
      final h1Size = tokens.h1.fontSize!;
      expect(h1Size, greaterThan(tokens.body.fontSize!));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownView(
              document: const MarkdownDocument(
                blocks: [
                  HeadingBlock(
                    level: 1,
                    runs: [
                      TextRun('TeamPilot '),
                      CodeRun('hello'),
                    ],
                  ),
                ],
              ),
              tokens: tokens,
            ),
          ),
        ),
      );

      final text = tester.widget<Text>(find.byType(Text).first);
      TextStyle? codeStyle;
      void visit(InlineSpan span) {
        if (span is TextSpan) {
          if (span.text == 'hello') codeStyle = span.style;
          for (final child in span.children ?? const <InlineSpan>[]) {
            visit(child);
          }
        }
      }

      visit(text.textSpan!);
      expect(codeStyle, isNotNull);
      expect(codeStyle!.fontSize, h1Size);
      expect(codeStyle!.fontFamily, 'Mono');
    },
  );
}
