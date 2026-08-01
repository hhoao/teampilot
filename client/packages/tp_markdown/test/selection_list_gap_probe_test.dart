import 'package:tp_markdown/tp_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('paragraphs use forced strut for uniform line boxes', (
    tester,
  ) async {
    final base = MarkdownTokens.test(blockGap: 24, listItemGap: 8);
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
      headingBottom: base.headingBottom,
      paragraphGap: base.paragraphGap,
      blockGap: 24,
      listItemGap: 8,
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
    expect(text.strutStyle, isNotNull);
    expect(text.strutStyle!.forceStrutHeight, isTrue);
    expect(text.strutStyle!.height, 1.65);
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
