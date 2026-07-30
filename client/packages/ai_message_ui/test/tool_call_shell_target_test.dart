import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Bash shows shell summary; collapsed shows \$ command + output', (
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
    expect(find.textContaining('git status --short'), findsOneWidget);
    expect(find.textContaining('M client/lib/a.dart'), findsOneWidget);
    expect(find.textContaining('Result:'), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    expect(find.textContaining('\$'), findsWidgets);
    expect(find.textContaining('git status --short'), findsOneWidget);
    expect(find.textContaining('M client/lib/a.dart'), findsOneWidget);
    expect(find.textContaining('Result:'), findsNothing);
    // Must not dump JSON args panel.
    expect(find.textContaining('"command"'), findsNothing);
  });

  testWidgets('collapsed output capped at 5 lines', (tester) async {
    final result = List.generate(7, (i) => 'line${i + 1}').join('\n');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Bash',
              args: {'command': 'seq 7'},
              result: result,
              status: AiToolCallStatus.complete,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('line1'), findsOneWidget);
    expect(find.textContaining('line5'), findsOneWidget);
    expect(find.textContaining('line6'), findsNothing);
    expect(find.textContaining('line7'), findsNothing);
  });

  testWidgets('tap mini panel toggles full output', (tester) async {
    final result = List.generate(7, (i) => 'line${i + 1}').join('\n');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Bash',
              args: {'command': 'seq 7'},
              result: result,
              status: AiToolCallStatus.complete,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('line6'), findsNothing);
    await tester.tap(find.textContaining('line3'));
    await tester.pumpAndSettle();
    expect(find.textContaining('line6'), findsOneWidget);
    expect(find.textContaining('line7'), findsOneWidget);
  });

  testWidgets('initiallyExpanded shows full output immediately', (tester) async {
    final result = List.generate(7, (i) => 'line${i + 1}').join('\n');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            initiallyExpanded: true,
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Bash',
              args: {'command': 'seq 7'},
              result: result,
              status: AiToolCallStatus.complete,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('line6'), findsOneWidget);
    expect(find.textContaining('line7'), findsOneWidget);
  });

  testWidgets('expanded shell output is not in SelectionContainer.disabled', (
    tester,
  ) async {
    final result = List.generate(7, (i) => 'line${i + 1}').join('\n');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: AiToolCallPartView(
              initiallyExpanded: true,
              part: AiToolCallPart(
                toolCallId: '1',
                toolName: 'Bash',
                args: {'command': 'seq 7'},
                result: result,
                status: AiToolCallStatus.complete,
              ),
            ),
          ),
        ),
      ),
    );

    final outputFinder = find.textContaining('line7');
    expect(outputFinder, findsOneWidget);
    expect(
      find.ancestor(
        of: outputFinder,
        matching: find.byWidgetPredicate(
          (w) => w is SelectionContainer && w.delegate == SelectionContainer.disabled,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('shell without description uses truncated command in header', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Shell',
              args: {'command': 'ls -la'},
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('ls -la'), findsWidgets);
    expect(find.textContaining('Used tool:'), findsNothing);
  });

  testWidgets('shell name without command stays legacy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Bash',
              args: {'description': 'no command'},
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Used tool:'), findsOneWidget);
  });

  testWidgets('Read still uses file summary chrome', (tester) async {
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
  });
}
