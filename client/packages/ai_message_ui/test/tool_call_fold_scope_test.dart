import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AiMessage messageWith(String id, List<AiMessagePart> parts) =>
      AiMessage(id: id, role: AiRole.assistant, parts: parts);

  Widget harness({AiToolCallFoldPredicate? shouldFold}) {
    final message = messageWith('m1', [
      const AiReasoningPart(text: 'r1'),
      AiToolCallPart(
        toolCallId: '1',
        toolName: 'Bash',
        status: AiToolCallStatus.complete,
        argsText: '{"command":"ls"}',
      ),
    ]);
    final view = AiMessageView(message: message);
    final wrapped = shouldFold == null
        ? view
        : AiToolCallFoldScope(shouldFold: shouldFold, child: view);
    return MaterialApp(
      home: Scaffold(
        body: Theme(
          data: ThemeData(extensions: [AiMessageTheme.test()]),
          child: wrapped,
        ),
      ),
    );
  }

  testWidgets('fold scope folds the tool call into the collapsed chain', (
    tester,
  ) async {
    await tester.pumpWidget(harness(shouldFold: (_) => true));
    await tester.pumpAndSettle();
    expect(find.textContaining('Thinking process'), findsOneWidget);
    // Bash 在折叠的链内,不单独渲染
    expect(find.textContaining('Bash'), findsNothing);
  });

  testWidgets('fold scope keeps unfolded tool call as standalone row', (
    tester,
  ) async {
    await tester.pumpWidget(harness(shouldFold: (_) => false));
    await tester.pumpAndSettle();
    // reasoning 仍折 → 恰一个链头
    expect(find.textContaining('Thinking process'), findsOneWidget);
    // Bash 独立成行
    expect(find.textContaining('Bash'), findsWidgets);
  });

  testWidgets('no scope defaults to folding', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.textContaining('Thinking process'), findsOneWidget);
    expect(find.textContaining('Bash'), findsNothing);
  });
}
