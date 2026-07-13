import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/compose/compose_focus_shell.dart';

void main() {
  testWidgets('focus deepens border and lifts light-mode shadow', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: Scaffold(
          body: ComposeFocusShell(
            focusNode: focusNode,
            color: Colors.white,
            borderColor: const Color(0xFF888888),
            child: Focus(
              focusNode: focusNode,
              child: const SizedBox(height: 48, width: 200),
            ),
          ),
        ),
      ),
    );

    final idle = _decoration(tester);
    expect(idle.border?.top.width, equals(1.5));
    expect(idle.boxShadow, isNotNull);
    expect(idle.boxShadow, isNotEmpty);

    focusNode.requestFocus();
    await tester.pumpAndSettle();

    final focused = _decoration(tester);
    // Same width when focused — no layout jump.
    expect(focused.border?.top.width, equals(idle.border?.top.width));
    expect(
      focused.border!.top.color.computeLuminance(),
      lessThan(idle.border!.top.color.computeLuminance()),
    );
    expect(
      focused.boxShadow!.first.blurRadius,
      greaterThan(idle.boxShadow!.first.blurRadius),
    );
  });

  testWidgets('dark mode keeps no shadow; focus only deepens border', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: const ColorScheme.dark(onSurface: Color(0xFFE0E0E0)),
        ),
        home: Scaffold(
          body: ComposeFocusShell(
            focusNode: focusNode,
            color: Colors.black,
            borderColor: const Color(0xFFAAAAAA),
            child: Focus(
              focusNode: focusNode,
              child: const SizedBox(height: 48, width: 200),
            ),
          ),
        ),
      ),
    );

    expect(_decoration(tester).boxShadow ?? const <BoxShadow>[], isEmpty);

    focusNode.requestFocus();
    await tester.pumpAndSettle();

    final focused = _decoration(tester);
    expect(focused.boxShadow ?? const <BoxShadow>[], isEmpty);
    expect(focused.border?.top.width, equals(1.5));
    expect(focused.border?.top.color.a, greaterThan(0.4));
  });

  testWidgets('floating idle also shows a soft border', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: Scaffold(
          body: ComposeFocusShell(
            focusNode: focusNode,
            floating: true,
            color: Colors.white,
            borderColor: const Color(0xFF888888),
            child: Focus(
              focusNode: focusNode,
              child: const SizedBox(height: 48, width: 200),
            ),
          ),
        ),
      ),
    );

    final idle = _decoration(tester);
    expect(idle.border?.top.width, equals(1.5));
    expect(idle.border?.top.color.a, greaterThan(0));

    focusNode.requestFocus();
    await tester.pumpAndSettle();

    final focused = _decoration(tester);
    expect(focused.border?.top.width, equals(1.5));
    expect(
      focused.border!.top.color.computeLuminance(),
      lessThan(idle.border!.top.color.computeLuminance()),
    );
  });
}

BoxDecoration _decoration(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.byType(AnimatedContainer),
  );
  return container.decoration! as BoxDecoration;
}
