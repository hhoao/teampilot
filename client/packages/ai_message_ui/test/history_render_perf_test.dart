import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
        extensions: const [AiMessageTheme()],
      ),
      home: Scaffold(body: SingleChildScrollView(child: body)),
    );
  }

  testWidgets('history opens with Show more for oversized content', (
    tester,
  ) async {
    final rows = [
      for (var r = 0; r < 20; r++) '| c$r-a | c$r-b |',
    ].join('\n');
    final markdown = '| A | B |\n| --- | --- |\n$rows';
    final message = AiMessage(
      id: 'a1',
      role: AiRole.assistant,
      parts: [AiTextPart(text: markdown)],
    );

    await tester.pumpWidget(
      wrap(
        AiMessageView(message: message, showActionBar: false),
        budget: const ContentCollapseBudget(maxTableRows: 4, maxChars: 100000),
      ),
    );

    // Claude-aligned: capped content mounts immediately (no blank defer).
    expect(find.text('Show more'), findsOneWidget);
    expect(find.text('c0-a'), findsOneWidget);
    expect(find.text('c19-a'), findsNothing);

    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();

    expect(find.text('Show less'), findsOneWidget);
    expect(find.text('c19-a'), findsOneWidget);
  });

  testWidgets('without history scope content is fully expanded', (tester) async {
    final rows = [
      for (var r = 0; r < 12; r++) '| c$r-a | c$r-b |',
    ].join('\n');
    final markdown = '| A | B |\n| --- | --- |\n$rows';
    final message = AiMessage(
      id: 'a1',
      role: AiRole.assistant,
      parts: [AiTextPart(text: markdown)],
    );

    await tester.pumpWidget(
      wrap(
        AiMessageView(message: message, showActionBar: false),
        history: false,
      ),
    );

    expect(find.text('Show more'), findsNothing);
    expect(find.text('c11-a'), findsOneWidget);
  });
}
