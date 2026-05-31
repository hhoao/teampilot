import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('input text uses bodyMedium scale from TextTheme', () {
    final theme = buildDarkTheme();
    expect(
      theme.textTheme.bodyLarge?.fontSize,
      theme.textTheme.bodyMedium?.fontSize,
    );
    final hintSize = theme.inputDecorationTheme.hintStyle?.fontSize;
    final inputSize = theme.textTheme.bodyLarge?.fontSize;
    expect(inputSize, AppTypographyScale.standard.bodyMedium);
    expect(hintSize, AppTypographyScale.standard.bodyMedium);
  });

  testWidgets('TextField merges theme hintStyle over M3 bodyLarge base', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: TextField(
            decoration: InputDecoration(hintText: 'hint'),
          ),
        ),
      ),
    );

    final textField = tester.widget<TextField>(find.byType(TextField));
    final theme = Theme.of(tester.element(find.byType(TextField)));
    final merged = textField.decoration!.applyDefaults(theme.inputDecorationTheme);

    expect(
      merged.hintStyle?.fontSize,
      lessThanOrEqualTo(theme.textTheme.bodyLarge!.fontSize!),
    );
  });
}
