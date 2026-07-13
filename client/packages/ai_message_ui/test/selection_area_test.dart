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
          parts: [
            AiTextPart(text: 'First paragraph.\n\nSecond paragraph.'),
          ],
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
}
