import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('user message aligns end; assistant aligns start', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AiMessageView(
                message: AiMessage(
                  id: 'u1',
                  role: AiRole.user,
                  parts: const [AiTextPart(text: 'hello user')],
                ),
              ),
              AiMessageView(
                message: AiMessage(
                  id: 'a1',
                  role: AiRole.assistant,
                  parts: const [AiTextPart(text: 'hello assistant')],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final userAlign = tester.widget<Align>(
      find
          .ancestor(
            of: find.textContaining('hello user'),
            matching: find.byType(Align),
          )
          .first,
    );
    final assistantAlign = tester.widget<Align>(
      find
          .ancestor(
            of: find.textContaining('hello assistant'),
            matching: find.byType(Align),
          )
          .first,
    );

    expect(userAlign.alignment, Alignment.centerRight);
    expect(assistantAlign.alignment, Alignment.centerLeft);
  });

  testWidgets('tool card shows toolName; tap expands args and result', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: const [
                AiToolCallPart(
                  toolCallId: 'tc1',
                  toolName: 'ReadFile',
                  args: {'path': '/tmp/x'},
                  result: 'file contents',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('ReadFile'), findsOneWidget);
    expect(find.textContaining('/tmp/x'), findsNothing);
    expect(find.textContaining('file contents'), findsNothing);

    await tester.tap(find.text('ReadFile'));
    await tester.pumpAndSettle();

    expect(find.textContaining('/tmp/x'), findsOneWidget);
    expect(find.textContaining('file contents'), findsOneWidget);
  });

  testWidgets('text part renders markdown bold', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: const [AiTextPart(text: 'say **bold** please')],
            ),
          ),
        ),
      ),
    );

    // MarkdownBody flattens **bold** into a TextSpan with FontWeight.bold.
    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    final hasBold = richTexts.any((rt) {
      var found = false;
      rt.text.visitChildren((span) {
        if (span is TextSpan &&
            span.text == 'bold' &&
            span.style?.fontWeight == FontWeight.bold) {
          found = true;
          return false;
        }
        return true;
      });
      return found;
    });
    expect(hasBold, isTrue);
  });
}
