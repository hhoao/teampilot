import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final message = AiMessage(
    id: '1',
    role: AiRole.assistant,
    parts: const [AiTextPart(text: 'hello')],
  );

  testWidgets('hidden hover ActionBar has no IconButton', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageActionBar(
            message: message,
            reveal: AiActionBarReveal.hover,
          ),
        ),
      ),
    );
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('always reveal builds IconButtons', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageActionBar(
            message: message,
            reveal: AiActionBarReveal.always,
          ),
        ),
      ),
    );
    expect(find.byType(IconButton), findsWidgets);
  });
}
