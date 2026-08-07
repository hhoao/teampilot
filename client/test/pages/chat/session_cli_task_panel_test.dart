import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/pages/chat/session_cli_task_panel.dart';
import 'package:teampilot/services/cli/tasks/cli_task_board.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

Widget _host(Widget child) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: Scaffold(body: child),
    ),
  );
}

CliTask _task(String subject, CliTaskStatus status) => CliTask(
  taskId: null,
  subject: subject,
  description: '',
  activeForm: '',
  status: status,
  seq: 0,
);

CliTaskBoard _board(List<CliTask> tasks) => CliTaskBoard(tasks: tasks);

void main() {
  testWidgets('hidden when there are no tasks', (tester) async {
    await tester.pumpWidget(
      _host(
        SessionCliTaskPanel(
          board: _board(const []),
          title: 'Tasks',
          countText: '0/0',
          moreLabel: (n) => '… +$n more',
        ),
      ),
    );
    expect(find.text('Tasks'), findsNothing);
  });

  testWidgets('collapsed pill shows in-progress task; tap expands to card',
      (tester) async {
    await tester.pumpWidget(
      _host(
        SessionCliTaskPanel(
          board: _board([
            _task('T1: first', CliTaskStatus.inProgress),
            _task('T2: second', CliTaskStatus.pending),
          ]),
          title: 'Tasks',
          countText: '0/2',
          moreLabel: (n) => '… +$n more',
        ),
      ),
    );
    // Collapsed pill: shows the in-progress subject, not the count/title.
    expect(find.text('T1: first'), findsOneWidget);
    expect(find.text('0/2'), findsNothing);
    expect(find.text('Tasks'), findsNothing);

    await tester.tap(find.text('T1: first'));
    await tester.pump();
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('T1: first'), findsOneWidget);
    expect(find.text('T2: second'), findsOneWidget);
  });

  testWidgets('collapsed pill falls back to count when nothing is in progress',
      (tester) async {
    await tester.pumpWidget(
      _host(
        SessionCliTaskPanel(
          board: _board([
            _task('T1: done', CliTaskStatus.completed),
            _task('T2: wait', CliTaskStatus.pending),
          ]),
          title: 'Tasks',
          countText: '1/2',
          moreLabel: (n) => '… +$n more',
        ),
      ),
    );
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('T1: done'), findsNothing);

    await tester.tap(find.text('1/2'));
    await tester.pump();
    expect(find.text('Tasks'), findsOneWidget);
  });

  testWidgets('completed tasks are struck through and counted', (tester) async {
    await tester.pumpWidget(
      _host(
        SessionCliTaskPanel(
          board: _board([
            _task('T1: done', CliTaskStatus.completed),
            _task('T2: wait', CliTaskStatus.pending),
          ]),
          title: 'Tasks',
          countText: '1/2',
          moreLabel: (n) => '… +$n more',
        ),
      ),
    );
    await tester.tap(find.text('1/2'));
    await tester.pump();
    expect(find.text('Tasks'), findsOneWidget);
    final doneText = tester.widget<Text>(find.text('T1: done'));
    expect(doneText.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('overflow shows +N more label', (tester) async {
    await tester.pumpWidget(
      _host(
        SessionCliTaskPanel(
          board: _board([
            for (var i = 1; i <= 8; i++) _task('T$i: item', CliTaskStatus.pending),
          ]),
          title: 'Tasks',
          countText: '0/8',
          moreLabel: (n) => '… +$n more',
          maxVisible: 6,
        ),
      ),
    );
    await tester.tap(find.text('0/8'));
    await tester.pump();
    expect(find.text('… +2 more'), findsOneWidget);
    expect(find.text('T1: item'), findsOneWidget);
    expect(find.text('T8: item'), findsNothing);
  });
}
