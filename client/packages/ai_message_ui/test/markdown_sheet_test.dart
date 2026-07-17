import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:ai_message_ui/src/markdown/compiled_text_part_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaultAiMarkdownSheet styles links and tables like aui', () {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      useMaterial3: true,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 14),
        titleLarge: TextStyle(fontSize: 22),
        titleMedium: TextStyle(fontSize: 16),
        titleSmall: TextStyle(fontSize: 14),
      ),
    );
    const aiTheme = AiMessageTheme();
    final sheet = defaultAiMarkdownSheet(theme, aiTheme);

    expect(sheet.a?.color, theme.colorScheme.primary);
    expect(
      sheet.a?.decoration,
      TextDecoration.underline,
    );
    expect(sheet.tableHead?.fontWeight, FontWeight.w600);
    expect(sheet.tableBorder, isNotNull);
    expect(sheet.tableHeadCellsDecoration, isA<BoxDecoration>());
    expect(
      (sheet.tableHeadCellsDecoration! as BoxDecoration).color,
      isNotNull,
    );
    expect(sheet.tableCellsPadding, isNotNull);
  });

  testWidgets(
    'AiTextPartView uses compiled path for GFM table and onTapLink',
    (tester) async {
      String? tappedHref;
      await tester.pumpWidget(
        MaterialApp(
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
      expect(find.byType(MarkdownBody), findsNothing);
      // Lite tables use Column/Row, not Flutter Table.
      expect(find.byType(Table), findsNothing);
      expect(find.textContaining('1'), findsOneWidget);
      await tester.tap(find.text('link'));
      await tester.pump();
      expect(tappedHref, 'https://example.com');
    },
  );
}
