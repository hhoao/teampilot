import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Cot collapsed by default; expand reveals reasoning without second tap',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: [
                AiReasoningPart(text: 'secret plan'),
                AiToolCallPart(
                  toolCallId: 'c1',
                  toolName: 'shell_command',
                  result: 'ok',
                ),
                AiTextPart(text: 'all done'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('secret plan'), findsNothing);
    expect(find.text('all done'), findsOneWidget);

    await tester.tap(find.textContaining('Thinking process'));
    await tester.pumpAndSettle();

    expect(find.textContaining('secret plan'), findsOneWidget);
    expect(find.textContaining('ok'), findsOneWidget);
  });

  testWidgets('multi-tool Cot expands all tool payloads without nested group click',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: [
                AiToolCallPart(
                  toolCallId: 'c1',
                  toolName: 'Read',
                  result: 'file-a',
                ),
                AiToolCallPart(
                  toolCallId: 'c2',
                  toolName: 'Grep',
                  result: 'file-b',
                ),
                const AiTextPart(text: 'summary'),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.textContaining('Thinking process'));
    await tester.pumpAndSettle();

    expect(find.textContaining('file-a'), findsOneWidget);
    expect(find.textContaining('file-b'), findsOneWidget);
    expect(find.textContaining('Used 2 tools'), findsNothing);
  });

  testWidgets('R/T-only turn is a single Cot with no trailing text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiMessageView(
            message: AiMessage(
              id: 'a1',
              role: AiRole.assistant,
              parts: [
                AiReasoningPart(text: 'only think'),
                AiToolCallPart(toolCallId: 'c1', toolName: 'Shell'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Thinking process'), findsOneWidget);
    expect(find.textContaining('only think'), findsNothing);
  });
}
