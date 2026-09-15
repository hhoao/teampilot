import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mailbox delivery does not badge the user bubble', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'u1',
              role: AiRole.user,
              deliveryChannel: 'mailbox',
              parts: const [AiTextPart(text: 'hello from mailbox')],
            ),
          ),
        ),
      ),
    );

    expect(find.text('hello from mailbox'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai-user-bubble-mailbox-marker')),
      findsNothing,
    );
    expect(find.byIcon(Icons.mail_outline), findsNothing);
  });

  testWidgets('user bubble hides mailbox marker when deliveryChannel is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'u1',
              role: AiRole.user,
              parts: const [AiTextPart(text: 'hello user')],
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('ai-user-bubble-mailbox-marker')),
      findsNothing,
    );
    expect(find.byIcon(Icons.mail_outline), findsNothing);
  });
}
