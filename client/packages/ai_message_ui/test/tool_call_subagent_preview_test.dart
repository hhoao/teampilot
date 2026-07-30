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

  testWidgets('isSubagentTool predicate gates subagent chrome', (tester) async {
    String? openedId;
    await tester.pumpWidget(
      MaterialApp(
        home: AiToolSubagentActionsScope(
          actions: AiToolSubagentActions(
            isSubagentTool: (n) => n == 'spawn_agent',
            onOpenSubagent: (id) async => openedId = id,
          ),
          child: const Scaffold(
            body: AiToolCallPartView(
              part: AiToolCallPart(
                toolCallId: 'spawn-1',
                toolName: 'spawn_agent',
                args: {'prompt': 'Do work'},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Used tool:'), findsNothing);
    expect(find.textContaining('spawn_agent'), findsOneWidget);

    await tester.tap(find.textContaining('Do work'));
    await tester.pumpAndSettle();
    expect(openedId, 'spawn-1');
  });

  testWidgets('isSubagentTool excludes non-matching tools', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiToolSubagentActionsScope(
          actions: AiToolSubagentActions(
            isSubagentTool: (n) => n == 'spawn_agent',
            onOpenSubagent: (_) async {},
          ),
          child: const Scaffold(
            body: AiToolCallPartView(
              part: AiToolCallPart(
                toolCallId: 'agent-1',
                toolName: 'Agent',
                args: {'description': 'Explore auth'},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Used tool:'), findsOneWidget);
  });

  testWidgets('spawn_agent uses core union fallback without predicate', (
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
                toolCallId: 'spawn-2',
                toolName: 'spawn_agent',
                args: {'prompt': 'Nested task'},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Used tool:'), findsNothing);
    await tester.tap(find.textContaining('Nested task'));
    await tester.pumpAndSettle();
    expect(openedId, 'spawn-2');
  });

  testWidgets('Bash with command uses shell chrome', (tester) async {
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
    expect(find.textContaining('Used tool:'), findsNothing);
    // Header summary + mini panel both show the command when no description.
    expect(find.textContaining('ls'), findsWidgets);
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

  testWidgets('SubagentPreviewScaffold: empty shows label; no compose', (
    tester,
  ) async {
    var backCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubagentPreviewScaffold(
            title: 'Explore auth',
            messages: const [],
            onBack: () => backCount++,
            emptyLabel: '暂无子会话内容',
          ),
        ),
      ),
    );

    expect(find.text('Explore auth'), findsOneWidget);
    expect(find.text('暂无子会话内容'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(backCount, 1);
  });

  testWidgets('SubagentPreviewScaffold: Read file open still works', (
    tester,
  ) async {
    AiToolFileTarget? openedFile;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiToolFileActionsScope(
            actions: AiToolFileActions(
              onOpenFile: (t) async => openedFile = t,
            ),
            child: AiToolSubagentActionsScope(
              actions: AiToolSubagentActions(
                onOpenSubagent: (_) async {},
              ),
              child: SubagentPreviewScaffold(
                title: 'Nested',
                messages: const [
                  AiMessage(
                    id: 'm1',
                    role: AiRole.assistant,
                    parts: [
                      AiToolCallPart(
                        toolCallId: 'read-1',
                        toolName: 'Read',
                        args: {
                          'file_path': 'lib/ai_history_seat.dart',
                          'offset': 110,
                          'limit': 80,
                        },
                      ),
                    ],
                  ),
                ],
                onBack: () {},
                emptyLabel: 'empty',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsNothing);

    // AiMessageView groups lone tools into collapsed chain-of-thought.
    await tester.tap(find.textContaining('Thinking process'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ai_history_seat.dart'), findsOneWidget);

    await tester.tap(find.textContaining('ai_history_seat.dart'));
    await tester.pumpAndSettle();
    expect(openedFile?.path, 'lib/ai_history_seat.dart');
  });
}
