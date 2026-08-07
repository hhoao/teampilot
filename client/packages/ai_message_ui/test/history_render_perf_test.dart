import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

void main() {
  Widget wrap(Widget child, {bool history = true, ContentCollapseBudget? budget}) {
    final body = history
        ? AiHistoryRenderScope(
            contentBudget: budget ?? ContentCollapseBudget.claudeAligned,
            child: child,
          )
        : child;
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        extensions: [AiMessageTheme.test()],
      ),
      home: Scaffold(body: SingleChildScrollView(child: body)),
    );
  }

  String tableMarkdown(int rows) => [
        '| A | B |',
        '| --- | --- |',
        for (var r = 0; r < rows; r++) '| c$r-a | c$r-b |',
      ].join('\n');

  testWidgets('assistant oversized table renders fully inline, no collapse', (
    tester,
  ) async {
    // Prose (tables/paragraphs) in assistant messages is content that must be
    // read immediately — never collapses, never shows a mask.
    final message = AiMessage(
      id: 'a1',
      role: AiRole.assistant,
      parts: [AiTextPart(text: tableMarkdown(20))],
    );

    await tester.pumpWidget(
      wrap(
        AiMessageView(message: message, showActionBar: false),
        budget: const ContentCollapseBudget(maxTableRows: 4, maxChars: 100000),
      ),
    );

    expect(find.text('c0-a'), findsOneWidget);
    expect(find.text('c19-a'), findsOneWidget); // full table, all rows
    expect(find.byIcon(Icons.expand_more), findsNothing); // no mask chevron
    expect(find.byType(VirtualMarkdownView), findsNothing);
  });

  testWidgets('user oversized message collapses to a mask and expands', (
    tester,
  ) async {
    final message = AiMessage(
      id: 'u1',
      role: AiRole.user,
      parts: [AiTextPart(text: tableMarkdown(20))],
    );

    await tester.pumpWidget(
      wrap(AiMessageView(message: message, showActionBar: false)),
    );
    await tester.pumpAndSettle();

    // Masked preview: head visible, tail absent, expand chevron present.
    expect(find.text('c0-a'), findsOneWidget);
    expect(find.text('c19-a'), findsNothing);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    expect(find.text('c19-a'), findsOneWidget);
    expect(find.byKey(kMaskCollapseBarKey), findsOneWidget);
    expect(find.byType(VirtualMarkdownView), findsNothing); // small → plain

    // Collapse back to the mask (bar may sit below the fold after expand).
    await tester.ensureVisible(find.byKey(kMaskCollapseBarKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kMaskCollapseBarKey));
    await tester.pumpAndSettle();
    expect(find.text('c19-a'), findsNothing);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
  });

  testWidgets('user oversized expanded content uses the virtualized markdown view', (
    tester,
  ) async {
    // Many blocks (over the 80-block threshold): expansion must go through
    // VirtualMarkdownView (bounded internal scroll), not a full Column layout.
    final markdown = [
      for (var i = 0; i < 120; i++) '## h$i\n\nparagraph $i with body text',
    ].join('\n\n');
    final message = AiMessage(
      id: 'big',
      role: AiRole.user,
      parts: [AiTextPart(text: markdown)],
    );

    await tester.pumpWidget(wrap(AiMessageView(message: message, showActionBar: false)));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    expect(find.byType(VirtualMarkdownView), findsOneWidget);
    expect(find.byKey(kMaskCollapseBarKey), findsOneWidget);
  });

  testWidgets('without history scope content is fully expanded', (tester) async {
    final message = AiMessage(
      id: 'a1',
      role: AiRole.assistant,
      parts: [AiTextPart(text: tableMarkdown(12))],
    );

    await tester.pumpWidget(
      wrap(
        AiMessageView(message: message, showActionBar: false),
        history: false,
      ),
    );

    expect(find.byIcon(Icons.expand_more), findsNothing);
    expect(find.text('c11-a'), findsOneWidget);
  });
}
