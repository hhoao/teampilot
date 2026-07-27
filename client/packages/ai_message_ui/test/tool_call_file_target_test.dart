import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('summary shows basename; tap opens; chevron expands', (
    tester,
  ) async {
    AiToolFileTarget? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: AiToolFileActionsScope(
          actions: AiToolFileActions(
            onOpenFile: (t) async => opened = t,
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
                result: 'ok',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Used tool:'), findsNothing);
    expect(find.textContaining('Read'), findsOneWidget);
    expect(find.textContaining('ai_history_seat.dart'), findsOneWidget);
    expect(find.textContaining('L110'), findsOneWidget);
    expect(find.textContaining('ok'), findsNothing);

    await tester.tap(find.textContaining('ai_history_seat.dart'));
    await tester.pumpAndSettle();
    expect(opened?.path, 'lib/ai_history_seat.dart');
    expect(opened?.startLine, 110);
    expect(find.textContaining('ok'), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(find.textContaining('ok'), findsOneWidget);
  });

  testWidgets('Bash keeps legacy Used tool chrome', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Bash',
              args: {'command': 'ls'},
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Used tool:'), findsOneWidget);
  });

  testWidgets('summary without onOpenFile renders plain basename', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Read',
              args: {'file_path': 'lib/foo.dart'},
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Used tool:'), findsNothing);
    expect(find.textContaining('foo.dart'), findsOneWidget);
    expect(find.textContaining('L'), findsNothing);
  });

  testWidgets('tap line range opens file when onOpenFile set', (tester) async {
    AiToolFileTarget? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: AiToolFileActionsScope(
          actions: AiToolFileActions(
            onOpenFile: (t) async => opened = t,
          ),
          child: const Scaffold(
            body: AiToolCallPartView(
              part: AiToolCallPart(
                toolCallId: '1',
                toolName: 'Read',
                args: {
                  'file_path': 'lib/foo.dart',
                  'offset': 5,
                  'limit': 3,
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.textContaining('L5-7'));
    await tester.pumpAndSettle();
    expect(opened?.path, 'lib/foo.dart');
    expect(opened?.startLine, 5);
    expect(opened?.endLine, 7);
  });
}
