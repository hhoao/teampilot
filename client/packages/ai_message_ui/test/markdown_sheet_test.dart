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
    expect(defaultSheet.h1Padding, const EdgeInsets.only(top: 16));
    expect(defaultSheet.h2Padding, const EdgeInsets.only(top: 12));
    expect(defaultSheet.h3Padding, const EdgeInsets.only(top: 8));

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
