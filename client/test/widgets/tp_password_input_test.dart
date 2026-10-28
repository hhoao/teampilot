import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/tp_password_input.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: ThemeData.light(),
    home: Scaffold(body: Center(child: child)),
  );

  TextField field(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  testWidgets('starts obscured and toggles visibility without losing text', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hunter2');
    addTearDown(controller.dispose);

    await tester.pumpWidget(wrap(TpPasswordInput(controller: controller)));

    expect(field(tester).obscureText, isTrue);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('password-visibility-toggle')));
    await tester.pump();

    expect(field(tester).obscureText, isFalse);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(controller.text, 'hunter2');

    await tester.tap(find.byKey(const ValueKey('password-visibility-toggle')));
    await tester.pump();

    expect(field(tester).obscureText, isTrue);
  });

  testWidgets('respects initiallyObscured and enabled', (tester) async {
    await tester.pumpWidget(
      wrap(
        TpPasswordInput(
          initiallyObscured: false,
          enabled: false,
          decoration: const InputDecoration(hintText: 'Token'),
        ),
      ),
    );

    expect(field(tester).obscureText, isFalse);
    expect(field(tester).enabled, isFalse);

    await tester.tap(
      find.byKey(const ValueKey('password-visibility-toggle')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(field(tester).obscureText, isFalse);
  });
}
