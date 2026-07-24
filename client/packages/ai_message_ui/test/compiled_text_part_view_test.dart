import 'package:ai_message_ui/src/markdown/compiled_text_part_view.dart';
import 'package:ai_message_ui/src/markdown/content_ir.dart';
import 'package:ai_message_ui/src/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpCompiled(
    WidgetTester tester, {
    required MessageContentDocument document,
    MarkdownTapLinkCallback? onTapLink,
    ValueChanged<SelectedContent?>? onSelectionChanged,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          extensions: [AiMessageTheme.test()],
        ),
        home: Scaffold(
          body: SelectionArea(
            onSelectionChanged: onSelectionChanged,
            child: SingleChildScrollView(
              child: CompiledTextPartView(
                document: document,
                onTapLink: onTapLink,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders heading text', (tester) async {
    await pumpCompiled(
      tester,
      document: const MessageContentDocument(
        blocks: [
          HeadingBlock(level: 2, runs: [TextRun('Section Title')]),
        ],
      ),
    );

    expect(find.text('Section Title'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);
  });

  testWidgets('renders ordered and task list text', (tester) async {
    await pumpCompiled(
      tester,
      document: const MessageContentDocument(
        blocks: [
          ListBlock(
            ordered: true,
            items: [
              ContentListItem(runs: [TextRun('First item')]),
              ContentListItem(runs: [TextRun('Second item')]),
            ],
          ),
          ListBlock(
            ordered: false,
            items: [
              ContentListItem(
                runs: [TextRun('done task')],
                isTaskChecked: true,
              ),
              ContentListItem(
                runs: [TextRun('open task')],
                isTaskChecked: false,
              ),
            ],
          ),
        ],
      ),
    );

    expect(find.textContaining('First item'), findsOneWidget);
    expect(find.textContaining('Second item'), findsOneWidget);
    expect(find.textContaining('done task'), findsOneWidget);
    expect(find.textContaining('open task'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);
  });

  testWidgets('link tap calls onTapLink callback', (tester) async {
    String? tappedHref;
    await pumpCompiled(
      tester,
      document: const MessageContentDocument(
        blocks: [
          ParagraphBlock(
            runs: [
              TextRun('See '),
              LinkRun(
                url: 'https://example.com',
                children: [TextRun('docs')],
              ),
              TextRun('.'),
            ],
          ),
        ],
      ),
      onTapLink: (text, href, title) {
        tappedHref = href;
      },
    );

    await tester.tap(find.textContaining('docs'));
    await tester.pump();
    expect(tappedHref, 'https://example.com');
    expect(find.byType(MarkdownBody), findsNothing);
  });

  testWidgets('table shows bold cell text', (tester) async {
    await pumpCompiled(
      tester,
      document: const MessageContentDocument(
        blocks: [
          TableBlock(
            headers: [
              InlineDocument(runs: [TextRun('A')]),
              InlineDocument(runs: [TextRun('B')]),
            ],
            rows: [
              [
                InlineDocument(runs: [TextRun('x')]),
                InlineDocument(
                  runs: [
                    StrongRun(children: [TextRun('bold-cell')]),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );

    // Row/Column flex layout — avoid Flutter Table / RenderTable.
    expect(find.byType(Table), findsNothing);
    expect(find.textContaining('bold-cell'), findsOneWidget);

    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    final boldSpan = richTexts
        .expand((r) => _flattenSpans(r.text))
        .whereType<TextSpan>()
        .firstWhere((s) => s.text == 'bold-cell');
    expect(boldSpan.style?.fontWeight, FontWeight.w700);

    expect(find.byType(MarkdownBody), findsNothing);
  });

  testWidgets('code block shows fence body', (tester) async {
    await pumpCompiled(
      tester,
      document: const MessageContentDocument(
        blocks: [
          CodeBlock(language: 'dart', text: 'print(42);\n'),
        ],
      ),
    );

    expect(find.textContaining('print(42);'), findsOneWidget);
    expect(find.textContaining('dart'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);
  });

  testWidgets('SelectionArea can select paragraph text', (tester) async {
    SelectedContent? selection;
    await pumpCompiled(
      tester,
      document: const MessageContentDocument(
        blocks: [
          ParagraphBlock(runs: [TextRun('Selectable paragraph body')]),
        ],
      ),
      onSelectionChanged: (value) => selection = value,
    );

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.textContaining('Selectable paragraph body'), findsOneWidget);

    // Leaves are plain Text/RichText under parent SelectionArea (not
    // SelectableText). Drag-select to prove the paragraph participates.
    final target = find.textContaining('Selectable paragraph body');
    final box = tester.getRect(target);
    final gesture = await tester.startGesture(
      Offset(box.left + 4, box.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(Offset(box.right - 4, box.center.dy));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selection?.plainText, contains('Selectable'));
  });

  testWidgets('must-compile docs have no MarkdownBody', (tester) async {
    await pumpCompiled(
      tester,
      document: const MessageContentDocument(
        blocks: [
          HeadingBlock(level: 1, runs: [TextRun('H')]),
          ParagraphBlock(runs: [TextRun('P')]),
          HorizontalRuleBlock(),
          BlockquoteBlock(
            blocks: [
              ParagraphBlock(runs: [TextRun('Q')]),
            ],
          ),
        ],
      ),
    );

    expect(find.byType(MarkdownBody), findsNothing);
  });

  testWidgets('unsupported slice falls back to MarkdownBody only', (
    tester,
  ) async {
    await pumpCompiled(
      tester,
      document: const MessageContentDocument(
        blocks: [
          ParagraphBlock(runs: [TextRun('before')]),
          UnsupportedBlock(rawMarkdown: '![alt](x.png)'),
          ParagraphBlock(runs: [TextRun('after')]),
        ],
      ),
    );

    expect(find.byType(MarkdownBody), findsOneWidget);
    final body = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(body.selectable, isFalse);
    expect(find.textContaining('before'), findsOneWidget);
    expect(find.textContaining('after'), findsOneWidget);
  });
}

Iterable<InlineSpan> _flattenSpans(InlineSpan span) sync* {
  yield span;
  if (span is TextSpan && span.children != null) {
    for (final child in span.children!) {
      yield* _flattenSpans(child);
    }
  }
}
