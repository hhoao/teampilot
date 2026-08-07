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
          showLessLabel: 'Show less',
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
          showLessLabel: 'Show less',
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
          showLessLabel: 'Show less',
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
          showLessLabel: 'Show less',
        ),
      ),
    );
    await tester.tap(find.text('1/2'));
    await tester.pump();
    expect(find.text('Tasks'), findsOneWidget);
    final doneText = tester.widget<Text>(find.text('T1: done'));
    expect(doneText.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('status icons are distinct, no loading spinner', (tester) async {
    await tester.pumpWidget(
      _host(
        SessionCliTaskPanel(
          board: _board([
            _task('T1: active', CliTaskStatus.inProgress),
            _task('T2: todo', CliTaskStatus.pending),
            _task('T3: done', CliTaskStatus.completed),
          ]),
          title: 'Tasks',
          countText: '1/3',
          moreLabel: (n) => '… +$n more',
          showLessLabel: 'Show less',
        ),
      ),
    );
    // Collapsed pill shows the in-progress task; tap it to expand.
    await tester.tap(find.text('T1: active'));
    await tester.pump();
    // in progress → arrow, pending → hollow circle, done → check.
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    // A material loading spinner must never represent an in-progress task.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('in-progress icon vertically centers on the first text line',
      (tester) async {
    const subject =
        'T1: a very long subject line that is going to wrap across two full '
        'lines inside the narrow task card';
    await tester.pumpWidget(
      _host(
        SessionCliTaskPanel(
          board: _board([_task(subject, CliTaskStatus.inProgress)]),
          title: 'Tasks',
          countText: '0/1',
          moreLabel: (n) => '… +$n more',
          showLessLabel: 'Show less',
        ),
      ),
    );
    // Collapsed pill shows the in-progress subject; tap to expand the card.
    await tester.tap(find.textContaining(subject));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    final iconCenter = tester.getCenter(find.byIcon(Icons.arrow_forward));
    final textRect = tester.getRect(find.text(subject));
    // The subject wraps to two lines; the 16px icon must center on the FIRST
    // line box, not the middle of the two-line block.
    final textStyle = tester.widget<Text>(find.text(subject)).style!;
    final lineHeight =
        (textStyle.fontSize ?? 12) * (textStyle.height ?? 1.0);
    final firstLineCenter = textRect.top + lineHeight / 2;
    expect((iconCenter.dy - firstLineCenter).abs(), lessThan(0.5));
    expect(iconCenter.dy, lessThan(textRect.center.dy));
  });

  testWidgets('overflow +N more expands to all tasks and collapses back',
      (tester) async {
    await tester.pumpWidget(
      _host(
        SessionCliTaskPanel(
          board: _board([
            for (var i = 1; i <= 8; i++) _task('T$i: item', CliTaskStatus.pending),
          ]),
          title: 'Tasks',
          countText: '0/8',
          moreLabel: (n) => '… +$n more',
          showLessLabel: 'Show less',
          maxVisible: 6,
        ),
      ),
    );
    await tester.tap(find.text('0/8'));
    await tester.pump();
    expect(find.text('… +2 more'), findsOneWidget);
    expect(find.text('T1: item'), findsOneWidget);
    expect(find.text('T8: item'), findsNothing);

    // Tap "+2 more" → all rows visible, footer becomes "Show less".
    await tester.tap(find.text('… +2 more'));
    await tester.pump();
    expect(find.text('T8: item'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);

    // Tap "Show less" → capped again.
    await tester.tap(find.text('Show less'));
    await tester.pump();
    expect(find.text('T8: item'), findsNothing);
    expect(find.text('… +2 more'), findsOneWidget);
  });

  testWidgets('truncated subject shows a tooltip with the full text; short does not',
      (tester) async {
    const long =
        'T1: this subject is extremely long and definitely wraps beyond the '
        'two line limit of the narrow task card so it gets truncated';
    const short = 'T2: short';
    await tester.pumpWidget(
      _host(
        SessionCliTaskPanel(
          board: _board([
            _task(long, CliTaskStatus.pending),
            _task(short, CliTaskStatus.pending),
          ]),
          title: 'Tasks',
          countText: '0/2',
          moreLabel: (n) => '… +$n more',
          showLessLabel: 'Show less',
        ),
      ),
    );
    // No in-progress task → pill shows count; expand the card.
    await tester.tap(find.text('0/2'));
    await tester.pump();
    expect(
      find.byWidgetPredicate((w) => w is Tooltip && w.message == long),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((w) => w is Tooltip && w.message == short),
      findsNothing,
    );
  });

  testWidgets('panel content is wrapped in a SelectionArea (copyable)',
      (tester) async {
    await tester.pumpWidget(
      _host(
        SessionCliTaskPanel(
          board: _board([_task('T1: item', CliTaskStatus.pending)]),
          title: 'Tasks',
          countText: '0/1',
          moreLabel: (n) => '… +$n more',
          showLessLabel: 'Show less',
        ),
      ),
    );
    expect(find.byType(SelectionArea), findsOneWidget);
  });
}
