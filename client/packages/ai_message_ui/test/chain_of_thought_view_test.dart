import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Cot expand keeps nested reasoning/tools collapsed by default',
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

      // Nested rows visible as triggers, payloads still hidden.
      expect(find.text('Reasoning'), findsOneWidget);
      expect(find.textContaining('shell_command'), findsOneWidget);
      expect(find.textContaining('secret plan'), findsNothing);
      expect(find.textContaining('ok'), findsNothing);

      await tester.tap(find.text('Reasoning'));
      await tester.pumpAndSettle();
      expect(find.textContaining('secret plan'), findsOneWidget);

      await tester.tap(find.textContaining('shell_command'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ok'), findsOneWidget);
    },
  );

  testWidgets(
    'theme cotExpand*OnOpen auto-expands nested kinds',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [
              AiMessageTheme.test(
                cotExpandReasoningOnOpen: true,
                cotExpandToolsOnOpen: true,
              ),
            ],
          ),
          home: const Scaffold(
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
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.textContaining('Thinking process'));
      await tester.pumpAndSettle();

      expect(find.textContaining('secret plan'), findsOneWidget);
      expect(find.textContaining('ok'), findsOneWidget);
    },
  );

  testWidgets(
    'theme cotExpandReasoningOnOpen expands reasoning only',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [
              AiMessageTheme.test(
                cotExpandReasoningOnOpen: true,
              ),
            ],
          ),
          home: const Scaffold(
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
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.textContaining('Thinking process'));
      await tester.pumpAndSettle();

      expect(find.textContaining('secret plan'), findsOneWidget);
      expect(find.textContaining('ok'), findsNothing);
    },
  );

  testWidgets(
    'multi-tool Cot keeps tool payloads collapsed until each row is tapped',
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

      expect(find.textContaining('file-a'), findsNothing);
      expect(find.textContaining('file-b'), findsNothing);
      expect(find.textContaining('Used 2 tools'), findsNothing);

      await tester.tap(find.textContaining('Read'));
      await tester.pumpAndSettle();
      expect(find.textContaining('file-a'), findsOneWidget);
      expect(find.textContaining('file-b'), findsNothing);

      await tester.tap(find.textContaining('Grep'));
      await tester.pumpAndSettle();
      expect(find.textContaining('file-b'), findsOneWidget);
    },
  );

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
