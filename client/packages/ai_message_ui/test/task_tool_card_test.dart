import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  final theme = ThemeData(
    useMaterial3: true,
    extensions: [AiMessageTheme.test()],
  );
  return MaterialApp(
    theme: theme,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('TaskCreate card shows subject and starts expanded', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const AiTaskToolCard(
          target: AiTaskCreateTarget(
            toolLabel: 'TaskCreate',
            subject: 'T1: do a thing',
            description: 'details',
            activeForm: 'Doing it',
          ),
        ),
      ),
    );
    expect(
      find.textContaining('TaskCreate', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('T1: do a thing', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('details'), findsOneWidget);
    expect(find.text('Doing it'), findsOneWidget);
    await tester.tap(find.text('Pending'));
    await tester.pump();
    expect(find.text('details'), findsNothing);
  });

  testWidgets('TaskUpdate card shows task id and status', (tester) async {
    await tester.pumpWidget(
      _host(
        const AiTaskToolCard(
          target: AiTaskUpdateTarget(
            toolLabel: 'TaskUpdate',
            taskId: '9',
            status: AiTaskStatus.inProgress,
            argsText: '{"taskId":"9"}',
          ),
        ),
      ),
    );
    expect(
      find.textContaining('TaskUpdate · T9', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('In progress'), findsOneWidget);
  });

  testWidgets('Todo list starts expanded and centers item rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const AiTaskToolCard(
          target: AiTodoListTarget(
            toolLabel: 'TodoWrite',
            items: [
              AiTodoItem(content: 'Task A', status: AiTaskStatus.inProgress),
              AiTodoItem(content: 'Task B', status: AiTaskStatus.pending),
            ],
          ),
        ),
      ),
    );
    expect(
      find.textContaining('TodoWrite', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('0/2'), findsOneWidget);
    expect(find.text('Task A'), findsOneWidget);
    expect(find.text('Task B'), findsOneWidget);
    final itemRow = tester.widget<Row>(
      find.ancestor(of: find.text('Task A'), matching: find.byType(Row)).first,
    );
    expect(itemRow.crossAxisAlignment, CrossAxisAlignment.center);
    await tester.tap(find.text('0/2'));
    await tester.pump();
    expect(find.text('Task A'), findsNothing);
  });
}
