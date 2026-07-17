import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('collapsed tool has no AnimatedSize body', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Bash',
              status: AiToolCallStatus.complete,
              argsText: '{"x":1}',
            ),
          ),
        ),
      ),
    );
    expect(find.byType(AnimatedSize), findsNothing);
    expect(find.textContaining('{'), findsNothing);
    expect(find.byType(Flexible), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(AnimatedScale), findsNothing);
  });

  testWidgets('collapsed reasoning has no markdown body', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiReasoningPartView(
            part: const AiReasoningPart(text: 'secret thoughts'),
          ),
        ),
      ),
    );
    expect(find.byType(AnimatedSize), findsNothing);
    expect(find.text('secret thoughts'), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(AnimatedScale), findsNothing);
  });
}
