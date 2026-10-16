import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/session_working_spinner.dart';

Finder _spinnerPaint() {
  return find.descendant(
    of: find.byType(SessionWorkingSpinner),
    matching: find.byType(CustomPaint),
  );
}

Future<void> _pumpIndicator(
  WidgetTester tester, {
  required bool working,
  bool waiting = false,
  bool backgroundRunning = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SessionWorkingIndicator(
            working: working,
            waiting: waiting,
            backgroundRunning: backgroundRunning,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'working spinner animation ticks paint without rebuilding widgets',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: SessionWorkingSpinner())),
        ),
      );

      expect(_spinnerPaint(), findsOneWidget);
      final paintBefore = tester.widget<CustomPaint>(_spinnerPaint());
      final painterBefore = paintBefore.painter;

      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(_spinnerPaint(), findsOneWidget);
      final paintAfter = tester.widget<CustomPaint>(_spinnerPaint());
      expect(
        identical(paintBefore, paintAfter),
        isTrue,
        reason:
            'vsync ticks must repaint the spinner layer, not rebuild '
            'CustomPaint / AnimatedBuilder (DevTools widget rebuild storm)',
      );
      expect(identical(painterBefore, paintAfter.painter), isTrue);
      expect(
        find.descendant(
          of: find.byType(SessionWorkingSpinner),
          matching: find.byType(AnimatedBuilder),
        ),
        findsNothing,
      );
    },
  );

  group('SessionWorkingIndicator precedence', () {
    testWidgets('waiting outranks working and background', (tester) async {
      await _pumpIndicator(
        tester,
        working: true,
        waiting: true,
        backgroundRunning: true,
      );
      expect(find.byType(SessionWaitingMarker), findsOneWidget);
      expect(find.byType(SessionWorkingSpinner), findsNothing);
      expect(find.byType(SessionBackgroundWorkMarker), findsNothing);
    });

    testWidgets('working outranks background', (tester) async {
      await _pumpIndicator(
        tester,
        working: true,
        backgroundRunning: true,
      );
      expect(find.byType(SessionWorkingSpinner), findsOneWidget);
      expect(find.byType(SessionBackgroundWorkMarker), findsNothing);
    });

    testWidgets('background alone shows a static hourglass, not a spinner', (
      tester,
    ) async {
      await _pumpIndicator(
        tester,
        working: false,
        backgroundRunning: true,
      );
      expect(find.byType(SessionBackgroundWorkMarker), findsOneWidget);
      expect(find.byType(SessionWorkingSpinner), findsNothing);
    });

    testWidgets('nothing active falls back to the idle dot', (tester) async {
      await _pumpIndicator(tester, working: false);
      expect(find.byType(SessionBackgroundWorkMarker), findsNothing);
      expect(find.byType(SessionWorkingSpinner), findsNothing);
      expect(find.byType(SessionWaitingMarker), findsNothing);
    });
  });
}
