import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_control_theme.dart';
import 'package:teampilot/theme/app_outline_input_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/textarea/app_textarea.dart';

void main() {
  ThemeData themeWithTightInput() {
    final base = ThemeData.light();
    final control = AppControlTheme.fromScale(AppTypographyScale.standard);
    return base.copyWith(
      extensions: [control],
      inputDecorationTheme: buildAppOutlineInputDecorationTheme(
        colorScheme: base.colorScheme,
        textTheme: base.textTheme,
        control: control,
      ),
    );
  }

  testWidgets('accepts typed text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeWithTightInput(),
        home: const Scaffold(body: AppTextarea()),
      ),
    );
    await tester.enterText(find.byType(TextField), 'hello');
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('respects enabled: false', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeWithTightInput(),
        home: const Scaffold(body: AppTextarea(enabled: false)),
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
  });

  testWidgets('decoration clears single-line tight height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeWithTightInput(),
        home: const Scaffold(
          body: AppTextarea(minHeight: 120, maxHeight: 300),
        ),
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    final c = field.decoration?.constraints;
    expect(c, isNotNull);
    expect(c!.maxHeight, isNot(equals(c.minHeight))); // not tightFor single track
  });
}
