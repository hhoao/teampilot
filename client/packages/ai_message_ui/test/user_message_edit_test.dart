import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpEditor(
    WidgetTester tester, {
    required Future<bool> Function(String) onSubmit,
    required VoidCallback onCancel,
  }) async {
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
            onSubmitEdit: onSubmit,
            onCancelEdit: onCancel,
          ),
        ),
      ),
    );
    // Attach the editor's focus node before sending key events.
    await tester.pump();
  }

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
            onSubmitEdit: (text) async {
              sent = text;
              return true;
            },
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

  testWidgets('Enter sends the edited text once', (tester) async {
    var sends = 0;
    String? sent;
    await pumpEditor(
      tester,
      onSubmit: (text) async {
        sends++;
        sent = text;
        return true;
      },
      onCancel: () {},
    );

    await tester.enterText(find.byType(TextField), 'changed');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sends, 1);
    expect(sent, 'changed');
  });

  testWidgets('Shift+Enter stays in the editor instead of sending', (
    tester,
  ) async {
    var sends = 0;
    await pumpEditor(
      tester,
      onSubmit: (_) async {
        sends++;
        return true;
      },
      onCancel: () {},
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(sends, 0);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Escape cancels the edit', (tester) async {
    var sends = 0;
    var cancels = 0;
    await pumpEditor(
      tester,
      onSubmit: (_) async {
        sends++;
        return true;
      },
      onCancel: () => cancels++,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(cancels, 1);
    expect(sends, 0);
  });

  testWidgets('unchanged text cancels without submitting', (tester) async {
    var sends = 0;
    var cancels = 0;
    await pumpEditor(
      tester,
      onSubmit: (_) async {
        sends++;
        return true;
      },
      onCancel: () => cancels++,
    );

    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(sends, 0);
    expect(cancels, 1);
  });

  testWidgets('Enter then Send still submits exactly once', (tester) async {
    var sends = 0;
    await pumpEditor(
      tester,
      onSubmit: (_) async {
        sends++;
        return true;
      },
      onCancel: () {},
    );

    await tester.enterText(find.byType(TextField), 'changed');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(sends, 1);
  });

  testWidgets('an assistant message never shows the edit action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            message: const AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: [AiTextPart(text: 'hi')],
            ),
            onEdit: () {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Edit message'), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
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
