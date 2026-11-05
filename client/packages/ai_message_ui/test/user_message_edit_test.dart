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

    // The editor paints over the bubble; the bubble itself stays mounted as a
    // hidden height sizer so opening the editor cannot move the thread.
    expect(find.byType(AiTextPartView), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'original');

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

  Widget userMessage({
    required bool editing,
    String text = '他有儿子吗',
    Future<List<String>> Function()? onPickAttachments,
  }) {
    return MaterialApp(
      theme: ThemeData(extensions: [AiMessageTheme.test()]),
      home: Scaffold(
        body: SizedBox(
          width: 600,
          child: AiMessageView(
            message: AiMessage(
              id: 'u1',
              role: AiRole.user,
              parts: [AiTextPart(text: text)],
            ),
            actionBarReveal: AiActionBarReveal.always,
            onEdit: () {},
            editing: editing,
            onSubmitEdit: (_) async => true,
            onCancelEdit: () {},
            onPickEditAttachments: onPickAttachments,
          ),
        ),
      ),
    );
  }

  testWidgets('the user action bar sits under the bubble, right aligned', (
    tester,
  ) async {
    await tester.pumpWidget(userMessage(editing: false));
    await tester.pumpAndSettle();

    final bubble = tester.getRect(
      find
          .ancestor(of: find.text('他有儿子吗'), matching: find.byType(ColoredBox))
          .first,
    );
    final bar = tester.getRect(find.byType(AiMessageActionBar));
    expect(bar.top, greaterThanOrEqualTo(bubble.bottom));
    expect((bar.right - bubble.right).abs(), lessThan(1));
  });

  testWidgets('opening the editor keeps the message height stable', (
    tester,
  ) async {
    await tester.pumpWidget(userMessage(editing: false));
    final collapsed = tester.getSize(find.byType(AiMessageView)).height;

    await tester.pumpWidget(userMessage(editing: true));
    await tester.pump();
    final expanded = tester.getSize(find.byType(AiMessageView)).height;

    // The editor paints over the bubble kept as a hidden sizer, so the slot
    // height does not change when it opens.
    expect(expanded, closeTo(collapsed, 1));
  });

  testWidgets('a long user message also keeps its height when edited', (
    tester,
  ) async {
    const long = 'first line\nsecond line\nthird line\nfourth line';
    await tester.pumpWidget(userMessage(editing: false, text: long));
    final collapsed = tester.getSize(find.byType(AiMessageView)).height;

    await tester.pumpWidget(userMessage(editing: true, text: long));
    await tester.pump();
    final expanded = tester.getSize(find.byType(AiMessageView)).height;

    expect(expanded, closeTo(collapsed, 1));
  });

  testWidgets('attach inserts its references into the draft', (tester) async {
    await tester.pumpWidget(
      userMessage(
        editing: true,
        onPickAttachments: () async => ['@docs/a.md', '@src/b.dart'],
      ),
    );
    await tester.enterText(find.byType(TextField), 'check');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.attach_file_rounded));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'check @docs/a.md @src/b.dart');
  });
}
