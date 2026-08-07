import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({
    required AiToolCallPart part,
    Map<String, AiToolCallBubbleBuilder> builders = const {},
  }) {
    final theme = ThemeData(
      useMaterial3: true,
      extensions: [AiMessageTheme.test()],
    );
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: AiToolCallBubbleScope(
          builders: builders,
          child: AiToolCallPartView(part: part),
        ),
      ),
    );
  }

  testWidgets('matched name renders custom bubble, not generic trigger',
      (tester) async {
    final part = AiToolCallPart(
      toolCallId: 'c',
      toolName: 'TaskCreate',
      args: const {'subject': 'T1: hello'},
      status: AiToolCallStatus.complete,
    );
    await tester.pumpWidget(
      host(
        part: part,
        builders: {
          'taskcreate': (context, p) => Text('BUBBLE-${p.toolName}'),
        },
      ),
    );
    expect(find.text('BUBBLE-TaskCreate'), findsOneWidget);
    expect(find.textContaining('Used tool', findRichText: true), findsNothing);
  });

  testWidgets('unmatched name still renders generic trigger', (tester) async {
    final part = AiToolCallPart(
      toolCallId: 'c',
      toolName: 'Glob',
      args: const {'pattern': 'lib/**/*.dart'},
      status: AiToolCallStatus.complete,
    );
    await tester.pumpWidget(host(part: part, builders: const {}));
    expect(find.textContaining('Used tool', findRichText: true), findsOneWidget);
  });
}
