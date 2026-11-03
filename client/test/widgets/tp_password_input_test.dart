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

  testWidgets('fetches a stored secret when revealing an empty field', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var reveals = 0;
    await tester.pumpWidget(
      wrap(
        TpPasswordInput(
          controller: controller,
          onReveal: () async {
            reveals++;
            return 'stored';
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('password-visibility-toggle')));
    await tester.pumpAndSettle();

    expect(reveals, 1);
    expect(controller.text, 'stored');
    expect(field(tester).obscureText, isFalse);
  });

  testWidgets('a cancelled reveal keeps the field masked and empty', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrap(TpPasswordInput(controller: controller, onReveal: () async => null)),
    );

    await tester.tap(find.byKey(const ValueKey('password-visibility-toggle')));
    await tester.pumpAndSettle();

    expect(controller.text, isEmpty);
    expect(field(tester).obscureText, isTrue);
  });

  testWidgets('does not overwrite typed text or call onReveal', (tester) async {
    final controller = TextEditingController(text: 'typed');
    addTearDown(controller.dispose);
    var reveals = 0;
    await tester.pumpWidget(
      wrap(
        TpPasswordInput(
          controller: controller,
          onReveal: () async {
            reveals++;
            return 'stored';
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('password-visibility-toggle')));
    await tester.pumpAndSettle();

    expect(reveals, 0);
    expect(controller.text, 'typed');
    expect(field(tester).obscureText, isFalse);
  });
}
