import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AiThread wraps idle messages in SelectionArea', (tester) async {
    final store = ExternalStoreAiThreadRuntime()
      ..setMessages([
        const AiMessage(
          id: '1',
          role: AiRole.assistant,
          parts: [AiTextPart(text: 'First paragraph.\n\nSecond paragraph.')],
        ),
      ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiThread(
            runtime: store,
            loadingBuilder: (_) => const Text('LOADING'),
            emptyBuilder: (_) => const Text('EMPTY'),
            errorBuilder: (_, __, ___) => const Text('ERR'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.textContaining('First paragraph'), findsOneWidget);
  });

  testWidgets('AiThread scroll view spans full width for empty-margin scroll', (
    tester,
  ) async {
    final store = ExternalStoreAiThreadRuntime()
      ..setMessages([
        const AiMessage(
          id: '1',
          role: AiRole.assistant,
          parts: [AiTextPart(text: 'hello')],
        ),
      ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 600,
            child: Theme(
              data: ThemeData(
                extensions: [AiMessageTheme.test(threadMaxWidth: 400)],
              ),
              child: AiThread(
                runtime: store,
                loadingBuilder: (_) => const Text('LOADING'),
                emptyBuilder: (_) => const Text('EMPTY'),
                errorBuilder: (_, __, ___) => const Text('ERR'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final listSize = tester.getSize(find.byType(ListView));
    // Scroll view fills the host (not the message maxWidth=400).
    expect(listSize.width, greaterThan(400));
    expect(listSize.width, equals(tester.getSize(find.byType(Scaffold)).width));
  });

  testWidgets('AiThread forwards selectionContextMenuBuilder', (tester) async {
    var built = false;
    final store = ExternalStoreAiThreadRuntime()
      ..setMessages([
        const AiMessage(
          id: '1',
          role: AiRole.assistant,
          parts: [AiTextPart(text: 'hello')],
        ),
      ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiThread(
            runtime: store,
            loadingBuilder: (_) => const Text('LOADING'),
            emptyBuilder: (_) => const Text('EMPTY'),
            errorBuilder: (_, __, ___) => const Text('ERR'),
            selectionContextMenuBuilder: (context, state) {
              built = true;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final area = tester.widget<SelectionArea>(find.byType(SelectionArea));
    expect(area.contextMenuBuilder, isNotNull);
    // Builder is only invoked when the toolbar is shown; wiring is enough.
    expect(built, isFalse);
  });
}
