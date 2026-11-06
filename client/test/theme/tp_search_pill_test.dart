import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets('pill decoration is a stadium search field', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Builder(
          builder: (ctx) {
            context = ctx;
            return const SizedBox();
          },
        ),
      ),
    );

    final decoration = tpSearchPillDecoration(
      context,
      hintText: 'Search messages',
    );
    final scheme = Theme.of(context).colorScheme;

    expect(decoration.hintText, 'Search messages');
    expect(decoration.filled, isTrue);
    expect(decoration.fillColor, scheme.surfaceContainer);
    expect(decoration.floatingLabelBehavior, FloatingLabelBehavior.never);
    expect(decoration.prefixIcon, isA<Icon>());

    final enabled = decoration.enabledBorder! as OutlineInputBorder;
    expect(
      enabled.borderRadius,
      const BorderRadius.all(Radius.circular(tpSearchPillRadius)),
    );
    final focused = decoration.focusedBorder! as OutlineInputBorder;
    expect(
      focused.borderRadius,
      const BorderRadius.all(Radius.circular(tpSearchPillRadius)),
    );
    expect(focused.borderSide.color, scheme.primary);
  });

  testWidgets('TpInput honors an explicit pill borderRadius', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const Scaffold(
          body: TpInput(borderRadius: tpSearchPillRadius),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    final border = field.decoration!.enabledBorder! as OutlineInputBorder;
    expect(
      border.borderRadius,
      const BorderRadius.all(Radius.circular(tpSearchPillRadius)),
    );
  });
}
