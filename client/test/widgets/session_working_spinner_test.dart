import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/session_working_spinner.dart';

Finder _spinnerPaint() {
  return find.descendant(
    of: find.byType(SessionWorkingSpinner),
    matching: find.byType(CustomPaint),
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
      expect(
        identical(painterBefore, paintAfter.painter),
        isTrue,
      );
      expect(
        find.descendant(
          of: find.byType(SessionWorkingSpinner),
          matching: find.byType(AnimatedBuilder),
        ),
        findsNothing,
      );
    },
  );
}
