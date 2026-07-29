import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('StrReplace shows basename + badge + mini-diff (not Used tool)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'StrReplace',
              args: {
                'file_path': 'lib/tp_sidebar_provider.dart',
                'old_string': 'final double mobileBreakpoint;',
                'new_string':
                    'final double mobileBreakpoint;\nfinal bool edgeOpenEnabled;',
                'start_line': 40,
              },
              result: 'ok',
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Used tool:'), findsNothing);
    expect(find.textContaining('tp_sidebar_provider.dart'), findsOneWidget);
    expect(find.textContaining('+'), findsWidgets);
    expect(find.textContaining('edgeOpenEnabled'), findsOneWidget);
    expect(find.textContaining('ok'), findsNothing);
  });

  testWidgets('expand grows same region; no Result: label or args JSON', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'StrReplace',
              args: {
                'file_path': 'lib/a.dart',
                'old_string': 'l1\nl2\nl3\nl4\nl5\nl6',
                'new_string': 'l1\nl2\nl3\nl4\nl5\nCHANGED',
              },
              result: 'ok',
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('CHANGED'), findsNothing);
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(find.textContaining('CHANGED'), findsOneWidget);
    expect(find.textContaining('Result:'), findsNothing);
    expect(find.textContaining('old_string'), findsNothing);
  });

  testWidgets('tap basename opens file with endLine', (tester) async {
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
                toolName: 'StrReplace',
                args: {
                  'file_path': 'lib/a.dart',
                  'old_string': 'x',
                  'new_string': 'y',
                  'start_line': 10,
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.textContaining('a.dart'));
    await tester.pumpAndSettle();
    expect(opened?.path, 'lib/a.dart');
    expect(opened?.startLine, 10);
    expect(opened?.endLine, isNotNull);
  });

  testWidgets('enrichEditContext success updates line numbers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiToolFileActionsScope(
          actions: AiToolFileActions(
            enrichEditContext: (hunk) async => AiEditHunk(
              path: hunk.path,
              addedCount: hunk.addedCount,
              removedCount: hunk.removedCount,
              startLine: 40,
              lines: [
                const AiEditLine(
                  kind: AiEditLineKind.context,
                  text: 'before',
                  lineNumber: 40,
                ),
                const AiEditLine(
                  kind: AiEditLineKind.add,
                  text: 'added',
                  lineNumber: 41,
                ),
              ],
            ),
          ),
          child: const Scaffold(
            body: AiToolCallPartView(
              part: AiToolCallPart(
                toolCallId: '1',
                toolName: 'StrReplace',
                args: {
                  'file_path': 'lib/a.dart',
                  'old_string': 'x',
                  'new_string': 'y',
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('40'), findsWidgets);
    expect(find.textContaining('before'), findsOneWidget);
  });

  testWidgets('Read still uses summary chrome', (tester) async {
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
    expect(find.textContaining('Read'), findsOneWidget);
    expect(find.textContaining('foo.dart'), findsOneWidget);
    expect(find.byIcon(Icons.terminal), findsNothing);
  });

  testWidgets('Bash with command still uses shell chrome, not edit card', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Bash',
              args: {
                'command': 'git status --short',
                'description': 'Check worktree git state',
              },
              result: ' M client/lib/a.dart',
              status: AiToolCallStatus.complete,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Used tool:'), findsNothing);
    expect(find.textContaining('Check worktree git state'), findsOneWidget);
    expect(find.textContaining('git status --short'), findsNothing);
    expect(find.textContaining('Result:'), findsNothing);
    expect(find.byIcon(Icons.terminal), findsOneWidget);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    expect(find.textContaining('\$'), findsWidgets);
    expect(find.textContaining('git status --short'), findsOneWidget);
    expect(find.textContaining('M client/lib/a.dart'), findsOneWidget);
    expect(find.textContaining('Result:'), findsNothing);
    expect(find.textContaining('"command"'), findsNothing);
  });
}
