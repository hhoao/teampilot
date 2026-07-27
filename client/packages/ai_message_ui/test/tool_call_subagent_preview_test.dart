import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Agent with onOpenSubagent: tap title opens; chevron expands', (
    tester,
  ) async {
    String? openedId;
    await tester.pumpWidget(
      MaterialApp(
        home: AiToolSubagentActionsScope(
          actions: AiToolSubagentActions(
            onOpenSubagent: (id) async => openedId = id,
          ),
          child: const Scaffold(
            body: AiToolCallPartView(
              part: AiToolCallPart(
                toolCallId: 'agent-1',
                toolName: 'Agent',
                args: {
                  'description': 'Explore auth',
                  'prompt': 'long prompt',
                },
                result: 'subagent done',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Used tool:'), findsNothing);
    expect(find.textContaining('Agent'), findsOneWidget);
    expect(find.textContaining('Explore auth'), findsOneWidget);
    expect(find.textContaining('subagent done'), findsNothing);

    await tester.tap(find.textContaining('Explore auth'));
    await tester.pumpAndSettle();
    expect(openedId, 'agent-1');
    expect(find.textContaining('subagent done'), findsNothing);

    openedId = null;
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(openedId, isNull);
    expect(find.textContaining('subagent done'), findsOneWidget);
  });

  testWidgets('Bash keeps legacy Used tool chrome', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiToolSubagentActionsScope(
          actions: AiToolSubagentActions(
            onOpenSubagent: (_) async {},
          ),
          child: const Scaffold(
            body: AiToolCallPartView(
              part: AiToolCallPart(
                toolCallId: '1',
                toolName: 'Bash',
                args: {'command': 'ls'},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Used tool:'), findsOneWidget);
  });

  testWidgets('Read still prefers file chrome when resolver hits', (
    tester,
  ) async {
    AiToolFileTarget? openedFile;
    String? openedSubagent;
    await tester.pumpWidget(
      MaterialApp(
        home: AiToolFileActionsScope(
          actions: AiToolFileActions(
            onOpenFile: (t) async => openedFile = t,
          ),
          child: AiToolSubagentActionsScope(
            actions: AiToolSubagentActions(
              onOpenSubagent: (id) async => openedSubagent = id,
            ),
            child: const Scaffold(
              body: AiToolCallPartView(
                part: AiToolCallPart(
                  toolCallId: '1',
                  toolName: 'Read',
                  args: {
                    'file_path': 'lib/ai_history_seat.dart',
                    'offset': 110,
                    'limit': 80,
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Used tool:'), findsNothing);
    expect(find.textContaining('ai_history_seat.dart'), findsOneWidget);

    await tester.tap(find.textContaining('ai_history_seat.dart'));
    await tester.pumpAndSettle();
    expect(openedFile?.path, 'lib/ai_history_seat.dart');
    expect(openedSubagent, isNull);
  });

  testWidgets('Agent without onOpenSubagent falls back to legacy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: 'agent-1',
              toolName: 'Agent',
              args: {'description': 'Explore auth'},
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Used tool:'), findsOneWidget);
    expect(find.textContaining('Agent'), findsOneWidget);
  });
}
