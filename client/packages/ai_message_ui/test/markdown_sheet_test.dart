import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:ai_message_ui/src/markdown/compiled_text_part_view.dart';
import 'package:ai_message_ui/src/markdown/content_ir.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CompiledMarkdownStyle.toMarkdownStyleSheet maps core tokens', () {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      useMaterial3: true,
    );
    final markdown = CompiledMarkdownStyle.test(scheme: theme.colorScheme);
    final sheet = markdown.toMarkdownStyleSheet();

    expect(sheet.a?.color, theme.colorScheme.primary);
    expect(sheet.a?.decoration, TextDecoration.underline);
    expect(sheet.tableHead?.fontWeight, FontWeight.w600);
    expect(sheet.tableBorder, isNotNull);
    expect(sheet.tableHeadCellsDecoration, isA<BoxDecoration>());
    expect(
      (sheet.tableHeadCellsDecoration! as BoxDecoration).color,
      isNotNull,
    );
    expect(sheet.tableCellsPadding, isNotNull);
    expect(sheet.p, markdown.body);
    expect(sheet.code, markdown.inlineCode);
  });

  test('CompiledMarkdownStyle table chrome maps to sheet (defaults + override)', () {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      useMaterial3: true,
    );
    final defaults = CompiledMarkdownStyle.test(scheme: theme.colorScheme);
    final defaultSheet = defaults.toMarkdownStyleSheet();

    expect(
      defaultSheet.tableCellsPadding,
      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    );
    // tableHeadBackground is Color? — null means resolve to mutedSurface@0.85
    expect(
      (defaultSheet.tableHeadCellsDecoration! as BoxDecoration).color,
      defaults.mutedSurface.withValues(alpha: 0.85),
    );
    expect(
      defaultSheet.h1Padding,
      const EdgeInsets.only(top: 16, bottom: 8),
    );
    expect(
      defaultSheet.h2Padding,
      const EdgeInsets.only(top: 12, bottom: 8),
    );
    expect(
      defaultSheet.h3Padding,
      const EdgeInsets.only(top: 8, bottom: 8),
    );

    const padding = EdgeInsets.symmetric(horizontal: 14, vertical: 8);
    final head = theme.colorScheme.onSurface.withValues(alpha: 0.04);
    // Construct with new named params on test() / constructor — no copyWith.
    final custom = CompiledMarkdownStyle.test(
      scheme: theme.colorScheme,
      tableCellsPadding: padding,
      tableHeadBackground: head,
      tableBodyBackground: Colors.transparent,
    );
    final sheet = custom.toMarkdownStyleSheet();
    expect(sheet.tableCellsPadding, padding);
    expect(
      (sheet.tableHeadCellsDecoration! as BoxDecoration).color,
      head,
    );
    expect(sheet.tableCellsDecoration, isA<BoxDecoration>());
    expect(
      (sheet.tableCellsDecoration! as BoxDecoration).color,
      Colors.transparent,
    );
  });

  test('headingTopSpacing maps into MarkdownStyleSheet paddings', () {
    final base = CompiledMarkdownStyle.test();
    final custom = CompiledMarkdownStyle(
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
      h1TopSpacing: 40,
      h2TopSpacing: 36,
      h3TopSpacing: 32,
      headingBottomSpacing: 10,
    );
    final sheet = custom.toMarkdownStyleSheet();
    expect(
      sheet.h1Padding,
      const EdgeInsets.only(top: 40, bottom: 10),
    );
    expect(
      sheet.h2Padding,
      const EdgeInsets.only(top: 36, bottom: 10),
    );
    expect(
      sheet.h3Padding,
      const EdgeInsets.only(top: 32, bottom: 10),
    );
    expect(custom.headingTopSpacing(2), 36);
    expect(custom.headingBottomSpacing, 10);
  });

  testWidgets('CompiledTextPartView table uses style table chrome', (tester) async {
    final base = CompiledMarkdownStyle.test();
    const padding = EdgeInsets.symmetric(horizontal: 14, vertical: 8);
    const head = Color(0x14000000);
    final style = CompiledMarkdownStyle(
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
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompiledTextPartView(
            style: style,
            document: const MessageContentDocument(
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
