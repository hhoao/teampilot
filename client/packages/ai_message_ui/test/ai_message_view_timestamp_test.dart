import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: child),
  );

  testWidgets('user message renders timestamp under the bubble', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        AiMessageView(
          message: const AiMessage(
            id: 'u1',
            role: AiRole.user,
            parts: [AiTextPart(text: 'hello')],
          ),
          timestampText: '11月6日 15:44',
        ),
      ),
    );
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('11月6日 15:44'), findsOneWidget);
    final tsTop = tester.getTopLeft(find.text('11月6日 15:44')).dy;
    final bubbleTop = tester.getTopLeft(find.text('hello')).dy;
    expect(tsTop, greaterThan(bubbleTop));
  });

  testWidgets('assistant message renders timestamp under the block', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        AiMessageView(
          message: const AiMessage(
            id: 'a1',
            role: AiRole.assistant,
            parts: [AiTextPart(text: 'reply')],
          ),
          timestampText: '15:44',
        ),
      ),
    );
    expect(find.text('15:44'), findsOneWidget);
    final tsTop = tester.getTopLeft(find.text('15:44')).dy;
    final bodyTop = tester.getTopLeft(find.text('reply')).dy;
    expect(tsTop, greaterThan(bodyTop));
  });

  testWidgets('null timestamp renders nothing extra', (tester) async {
    await tester.pumpWidget(
      host(
        AiMessageView(
          message: const AiMessage(
            id: 'u2',
            role: AiRole.user,
            parts: [AiTextPart(text: 'hi')],
          ),
        ),
      ),
    );
    expect(find.text('15:44'), findsNothing);
  });
}
