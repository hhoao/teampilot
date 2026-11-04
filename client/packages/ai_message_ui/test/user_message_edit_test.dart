import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('editing replaces the user bubble and sends trimmed text', (
    tester,
  ) async {
    String? sent;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AiMessageTheme.test()]),
        home: Scaffold(
          body: AiMessageView(
            message: const AiMessage(
              id: 'u1',
              role: AiRole.user,
              parts: [AiTextPart(text: 'original')],
            ),
            editing: true,
            onSubmitEdit: (text) => sent = text,
            onCancelEdit: () {},
          ),
        ),
      ),
    );

    // The bubble body is replaced by the editor, which is seeded with the
    // original text (`find.text` would also match the field's EditableText).
    expect(find.byType(AiTextPartView), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('original'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  changed  ');
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(sent, 'changed');
  });

  testWidgets('the bar offers edit on a user message', (tester) async {
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageActionBar(
            message: const AiMessage(
              id: 'u1',
              role: AiRole.user,
              parts: [AiTextPart(text: 'hi')],
            ),
            reveal: AiActionBarReveal.always,
            onEdit: () => edits++,
            editLabel: 'Edit message',
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Edit message'));
    expect(edits, 1);
  });
}
