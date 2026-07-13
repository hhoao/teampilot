import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
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

  testWidgets('AiTextPartView renders GFM table and forwards onTapLink', (
    tester,
  ) async {
    String? tappedHref;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiTextPartView(
            text: '| A | B |\n| --- | --- |\n| 1 | 2 |\n\n[link](https://example.com)',
            onTapLink: (text, href, title) {
              tappedHref = href;
            },
          ),
        ),
      ),
    );

    expect(find.byType(Table), findsOneWidget);
    await tester.tap(find.text('link'));
    await tester.pump();
    expect(tappedHref, 'https://example.com');
  });
}
