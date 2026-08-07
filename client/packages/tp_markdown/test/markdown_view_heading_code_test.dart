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
        listItemGap: base.listItemGap,
        listIndent: base.listIndent,
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

  testWidgets('oversized code block collapses to a fade mask and expands', (
    tester,
  ) async {
    final code = List.generate(
      400,
      (i) => 'line $i ${'x' * 40}',
    ).join('\n'); // ~18 KB, over the collapse threshold
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownView(
              document: MarkdownDocument(
                blocks: [CodeBlock(language: 'dart', text: code)],
              ),
              tokens: MarkdownTokens.test(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Masked: expand chevron present, the tail is not mounted.
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(find.textContaining('line 399'), findsNothing);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
    expect(find.textContaining('line 399'), findsOneWidget);
  });

  testWidgets('foldExpandFull code expands to full natural height (no shell)', (
    tester,
  ) async {
    final code = List.generate(400, (i) => 'line $i ${'x' * 40}').join('\n');
    await tester.pumpWidget(
      MaterialApp(
        home: MarkdownDisplayModeScope(
          codeBlockMode: ContentDisplayMode.foldExpandFull,
          child: Scaffold(
            body: SingleChildScrollView(
              child: MarkdownView(
                document: MarkdownDocument(
                  blocks: [CodeBlock(language: 'dart', text: code)],
                ),
                tokens: MarkdownTokens.test(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Masked by default; expand chevron present, tail absent.
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(find.textContaining('line 399'), findsNothing);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();

    // Full natural height: the full code is mounted, no inner scroll shell,
    // and the panel is as tall as the code (not clamped to the collapsed height).
    expect(find.textContaining('line 399'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget); // outer only
    final panel = find
        .ancestor(
          of: find.textContaining('line 0'),
          matching: find.byType(DecoratedBox),
        )
        .first;
    expect(tester.getRect(panel).height, greaterThan(1000));
  });

  testWidgets('flatten code renders full natural height with no mask', (
    tester,
  ) async {
    final code = List.generate(400, (i) => 'line $i ${'x' * 40}').join('\n');
    await tester.pumpWidget(
      MaterialApp(
        home: MarkdownDisplayModeScope(
          codeBlockMode: ContentDisplayMode.flatten,
          child: Scaffold(
            body: SingleChildScrollView(
              child: MarkdownView(
                document: MarkdownDocument(
                  blocks: [CodeBlock(language: 'dart', text: code)],
                ),
                tokens: MarkdownTokens.test(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No mask chevron; full code mounted.
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    expect(find.textContaining('line 399'), findsOneWidget);
  });
}
