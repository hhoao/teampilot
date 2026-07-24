import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:ai_message_ui/src/markdown/compiled_text_part_view.dart';
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
