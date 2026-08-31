import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

Widget _host(Widget child) {
  final theme = ThemeData(
    useMaterial3: true,
    extensions: [AiMessageTheme.test()],
  );
  return MaterialApp(
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
      child: Scaffold(body: child),
    ),
  );
}

AiTaskBoardItem _item(String subject, AiTaskStatus status) =>
    AiTaskBoardItem(subject: subject, status: status);

void main() {
  testWidgets('hidden when there are no tasks', (tester) async {
    await tester.pumpWidget(_host(const AiTaskBoardPanel(items: [])));
    expect(find.text('Tasks'), findsNothing);
  });

  testWidgets('collapsed pill shows in-progress task; tap expands to card', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AiTaskBoardPanel(
          items: [
            _item('T1: first', AiTaskStatus.inProgress),
            _item('T2: second', AiTaskStatus.pending),
          ],
        ),
      ),
    );
    expect(find.text('T1: first'), findsOneWidget);
    expect(find.text('0/2'), findsNothing);
    expect(find.text('Tasks'), findsNothing);

    await tester.tap(find.text('T1: first'));
    await tester.pump();
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('T1: first'), findsOneWidget);
    expect(find.text('T2: second'), findsOneWidget);
  });

  testWidgets(
    'collapsed pill falls back to count when nothing is in progress',
    (tester) async {
      await tester.pumpWidget(
        _host(
          AiTaskBoardPanel(
            items: [
              _item('T1: done', AiTaskStatus.completed),
              _item('T2: wait', AiTaskStatus.pending),
            ],
          ),
        ),
      );
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('T1: done'), findsNothing);

      await tester.tap(find.text('1/2'));
      await tester.pump();
      expect(find.text('Tasks'), findsOneWidget);
    },
  );

  testWidgets('collapsed pill docks collapsedLeading left of the task data', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AiTaskBoardPanel(
          items: [_item('T1: first', AiTaskStatus.inProgress)],
          collapsedLeading: const Icon(
            Icons.add_alert,
            key: Key('leading-probe'),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('leading-probe')), findsOneWidget);
    expect(find.text('T1: first'), findsOneWidget);

    // Expanded card shows only the task board; the docked control lives in
    // the collapsed pill.
    await tester.tap(find.text('T1: first'));
    await tester.pump();
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.byKey(const Key('leading-probe')), findsNothing);
  });

  testWidgets('empty board still hosts the collapsedLeading control', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AiTaskBoardPanel(
          items: const [],
          collapsedLeading: const Icon(
            Icons.add_alert,
            key: Key('leading-probe'),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('leading-probe')), findsOneWidget);
  });

  testWidgets('completed tasks are struck through and counted', (tester) async {
    await tester.pumpWidget(
      _host(
        AiTaskBoardPanel(
          items: [
            _item('T1: done', AiTaskStatus.completed),
            _item('T2: wait', AiTaskStatus.pending),
          ],
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
        AiTaskBoardPanel(
          items: [
            _item('T1: active', AiTaskStatus.inProgress),
            _item('T2: todo', AiTaskStatus.pending),
            _item('T3: done', AiTaskStatus.completed),
          ],
        ),
      ),
    );
    await tester.tap(find.text('T1: active'));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('in-progress icon vertically centers on the first text line', (
    tester,
  ) async {
    const subject =
        'T1: a very long subject line that is going to wrap across two full '
        'lines inside the narrow task card';
    await tester.pumpWidget(
      _host(AiTaskBoardPanel(items: [_item(subject, AiTaskStatus.inProgress)])),
    );
    await tester.tap(find.textContaining(subject));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    final iconCenter = tester.getCenter(find.byIcon(Icons.arrow_forward));
    final textRect = tester.getRect(find.text(subject));
    final textStyle = tester.widget<Text>(find.text(subject)).style!;
    final lineHeight = (textStyle.fontSize ?? 12) * (textStyle.height ?? 1.0);
    final firstLineCenter = textRect.top + lineHeight / 2;
    expect((iconCenter.dy - firstLineCenter).abs(), lessThan(0.5));
    expect(iconCenter.dy, lessThan(textRect.center.dy));
  });

  testWidgets('overflow +N more expands to all tasks and collapses back', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AiTaskBoardPanel(
          items: [
            for (var i = 1; i <= 8; i++)
              _item('T$i: item', AiTaskStatus.pending),
          ],
          maxVisible: 6,
        ),
      ),
    );
    await tester.tap(find.text('0/8'));
    await tester.pump();
    expect(find.text('… +2 more'), findsOneWidget);
    expect(find.text('T1: item'), findsOneWidget);
    expect(find.text('T8: item'), findsNothing);

    await tester.tap(find.text('… +2 more'));
    await tester.pump();
    expect(find.text('T8: item'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);

    await tester.tap(find.text('Show less'));
    await tester.pump();
    expect(find.text('T8: item'), findsNothing);
    expect(find.text('… +2 more'), findsOneWidget);
  });

  testWidgets(
    'truncated subject shows a tooltip with the full text; short does not',
    (tester) async {
      const long =
          'T1: this subject is extremely long and definitely wraps beyond the '
          'two line limit of the narrow task card so it gets truncated';
      const short = 'T2: short';
      await tester.pumpWidget(
        _host(
          AiTaskBoardPanel(
            items: [
              _item(long, AiTaskStatus.pending),
              _item(short, AiTaskStatus.pending),
            ],
          ),
        ),
      );
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
    },
  );

  testWidgets('collapsed and expanded cards draw a border and shadow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AiTaskBoardPanel(items: [_item('T1: first', AiTaskStatus.inProgress)]),
      ),
    );

    ShapeBorder? panelShape() {
      final materials = tester.widgetList<Material>(find.byType(Material));
      for (final material in materials) {
        final shape = material.shape;
        if (shape is RoundedRectangleBorder && shape.side.width > 0) {
          return shape;
        }
      }
      return null;
    }

    BoxDecoration? panelShadow() {
      final boxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
      for (final box in boxes) {
        final decoration = box.decoration;
        if (decoration is BoxDecoration &&
            (decoration.boxShadow?.isNotEmpty ?? false)) {
          return decoration;
        }
      }
      return null;
    }

    expect(panelShape(), isNotNull);
    expect(panelShadow(), isNotNull);

    await tester.tap(find.text('T1: first'));
    await tester.pump();

    expect(panelShape(), isNotNull);
    expect(panelShadow(), isNotNull);
  });

  testWidgets('panel content is wrapped in a SelectionArea (copyable)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(AiTaskBoardPanel(items: [_item('T1: item', AiTaskStatus.pending)])),
    );
    expect(find.byType(SelectionArea), findsOneWidget);
  });

  testWidgets(
    'collapsed count pill is selection-disabled so taps are not stolen by drag',
    (tester) async {
      await tester.pumpWidget(
        _host(
          AiTaskBoardPanel(
            items: [
              _item('T1: done', AiTaskStatus.completed),
              _item('T2: wait', AiTaskStatus.pending),
            ],
          ),
        ),
      );

      expect(
        find.ancestor(
          of: find.text('1/2'),
          matching: find.byType(SelectionDeadZone),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('1/2'));
      await tester.pump();
      expect(find.text('Tasks'), findsOneWidget);
    },
  );

  testWidgets('long task list is height-capped and scrolls internally', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AiTaskBoardPanel(
          items: [
            for (var i = 1; i <= 20; i++)
              _item('T$i: item', AiTaskStatus.pending),
          ],
          maxVisible: 6,
        ),
      ),
    );
    await tester.tap(find.text('0/20'));
    await tester.pump();
    await tester.tap(find.text('… +14 more'));
    await tester.pump();

    final cardSize = tester.getSize(find.byType(AiTaskBoardPanel));
    expect(cardSize.height, lessThan(500));
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text('T20: item'), findsOneWidget);
  });
}
