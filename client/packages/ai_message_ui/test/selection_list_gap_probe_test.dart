import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:ai_message_ui/src/markdown/compiled_markdown_style.dart';
import 'package:ai_message_ui/src/markdown/compiled_text_part_view.dart';
import 'package:ai_message_ui/src/markdown/ir/markdown_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compiled paragraphs use forced strut like MarkdownBody', (
    tester,
  ) async {
    final s = CompiledMarkdownStyle.test();
    final body = s.body.copyWith(height: 1.65);
    final style = CompiledMarkdownStyle(
      body: body,
      h1: s.h1,
      h2: s.h2,
      h3: s.h3,
      h4: s.h4,
      h5: s.h5,
      h6: s.h6,
      link: s.link,
      inlineCode: body,
      codeBlock: s.codeBlock,
      codeLanguage: s.codeLanguage,
      listBullet: body,
      blockquote: s.blockquote,
      tableHead: s.tableHead,
      tableBody: body,
      mutedSurface: s.mutedSurface,
      borderColor: s.borderColor,
      codeBlockRadius: s.codeBlockRadius,
      blockSpacing: 24,
      listItemSpacing: 8,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: CompiledTextPartView(
              style: style,
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
    final style = CompiledMarkdownStyle.test();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: CompiledTextPartView(
              style: style,
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
