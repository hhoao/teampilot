import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_control_theme.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test(
    'input and standard button min heights share AppControlTheme.height',
    () {
      final theme = buildDarkTheme();
      final control = theme.extension<AppControlTheme>()!;
      final inputMin = theme.inputDecorationTheme.constraints?.minHeight;
      expect(inputMin, control.height);

      Size? minOf(ButtonStyle? style) => style?.minimumSize?.resolve({});
      expect(minOf(theme.filledButtonTheme.style)?.height, control.height);
      expect(minOf(theme.outlinedButtonTheme.style)?.height, control.height);
      expect(minOf(theme.elevatedButtonTheme.style)?.height, control.height);
      expect(minOf(theme.textButtonTheme.style)?.height, control.height);
    },
  );

  test('control height tracks typography scale', () {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);
    expect(
      comfy.extension<AppControlTheme>()!.height,
      greaterThan(std.extension<AppControlTheme>()!.height),
    );
    expect(
      comfy.inputDecorationTheme.constraints?.minHeight,
      comfy.extension<AppControlTheme>()!.height,
    );
  });

  testWidgets('FilledButton and tonal keep distinct scheme foregrounds', (
    tester,
  ) async {
    final theme = buildDarkTheme();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(
            children: [
              FilledButton(onPressed: () {}, child: const Text('filled')),
              FilledButton.tonal(onPressed: () {}, child: const Text('tonal')),
            ],
          ),
        ),
      ),
    );

    Color fg(String label) {
      final element = tester.element(find.text(label));
      return DefaultTextStyle.of(element).style.color!;
    }

    expect(fg('filled'), theme.colorScheme.onPrimary);
    expect(fg('tonal'), theme.colorScheme.onSecondaryContainer);
  });

  test('filled/outlined/elevated retain stadium-like shape after merge', () {
    final theme = buildDarkTheme();
    OutlinedBorder? shapeOf(ButtonStyle? style) {
      final s = style?.shape?.resolve({});
      return s is OutlinedBorder ? s : null;
    }

    bool looksPill(OutlinedBorder? b) {
      if (b == null) return false;
      if (b is StadiumBorder) return true;
      if (b is RoundedRectangleBorder) {
        final r = b.borderRadius;
        if (r is BorderRadius) {
          return r.topLeft.x >= 20; // pill-ish vs input 8
        }
      }
      return false;
    }

    expect(looksPill(shapeOf(theme.filledButtonTheme.style)), isTrue);
    expect(looksPill(shapeOf(theme.outlinedButtonTheme.style)), isTrue);
    expect(looksPill(shapeOf(theme.elevatedButtonTheme.style)), isTrue);
  });
}
