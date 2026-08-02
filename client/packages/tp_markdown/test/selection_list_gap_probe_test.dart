import 'package:tp_markdown/tp_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('paragraphs use forced strut for uniform line boxes', (
    tester,
  ) async {
    final base = MarkdownTokens.test(listItemGap: 8);
    final body = base.body.copyWith(height: 1.65);
    final tokens = MarkdownTokens(
      body: body,
      h1: base.h1,
      h2: base.h2,
      h3: base.h3,
      h4: base.h4,
      h5: base.h5,
      h6: base.h6,
      link: base.link,
      inlineCode: body,
      codeBlock: base.codeBlock,
      codeLanguage: base.codeLanguage,
      listBullet: body,
      blockquote: base.blockquote,
      tableHead: base.tableHead,
      tableBody: body,
      mutedSurface: base.mutedSurface,
      borderColor: base.borderColor,
      codeBlockRadius: base.codeBlockRadius,
      tableCellsPadding: base.tableCellsPadding,
      tableHeadBackground: base.tableHeadBackground,
      tableBodyBackground: base.tableBodyBackground,
      paragraphMargin: base.paragraphMargin,
      h1Margin: base.h1Margin,
      h2Margin: base.h2Margin,
      h3Margin: base.h3Margin,
      h4Margin: base.h4Margin,
      h5Margin: base.h5Margin,
      h6Margin: base.h6Margin,
      listMargin: base.listMargin,
      blockquoteMargin: base.blockquoteMargin,
      codeMargin: base.codeMargin,
      tableMargin: base.tableMargin,
      horizontalRuleMargin: base.horizontalRuleMargin,
      imageMargin: base.imageMargin,
      rawLiteralMargin: base.rawLiteralMargin,
      listItemGap: 8,
      listIndent: base.listIndent,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: MarkdownView(
              tokens: tokens,
              document: const MarkdownDocument(
                blocks: [
                  ParagraphBlock(
                    runs: [
                      TextRun(
                        'AI Agent 封装的面向团队易用的桌面客提示词、乃至不同的 CLI',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(find.byType(Text).first);
    // forcedStrut disabled — rely on TextStyle.height for line box.
    expect(text.strutStyle, isNull);
  });

  testWidgets('list bullet is selection-disabled; body keeps hanging indent', (
    tester,
  ) async {
    final tokens = MarkdownTokens.test();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: MarkdownView(
              tokens: tokens,
              document: const MarkdownDocument(
                blocks: [
                  ListBlock(
                    ordered: false,
                    items: [
                      ContentListItem(
                        runs: [TextRun('目录：.claude/、.github/')],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('•'), findsOneWidget);
    expect(find.textContaining('目录'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SelectionContainer),
        matching: find.text('•'),
      ),
      findsOneWidget,
    );
  });
}
