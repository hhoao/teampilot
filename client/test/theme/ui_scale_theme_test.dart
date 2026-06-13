import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_spacing.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('text theme font sizes scale with the text-size (typography) scale', () {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);

    expect(
      comfy.textTheme.bodyMedium!.fontSize!,
      greaterThan(std.textTheme.bodyMedium!.fontSize!),
    );
  });

  test('button label role (labelLarge) scales with the text-size scale', () {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);

    // M3 TextButton/OutlinedButton/FilledButton use labelLarge.
    expect(
      comfy.textTheme.labelLarge!.fontSize!,
      greaterThan(std.textTheme.labelLarge!.fontSize!),
    );
  });

  test('spacing tokens are fixed (independent of the text-size scale)', () {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);

    // Text size scales fonts only; padding does not follow it (the whole-UI
    // UiZoom is the knob that scales spacing).
    expect(std.extension<AppSpacingTheme>()!.md, AppSpacingTheme.mdBase);
    expect(comfy.extension<AppSpacingTheme>()!.md, AppSpacingTheme.mdBase);
  });

  testWidgets('context.uiScale is fixed at 1.0 (spacing is not text-scaled)', (
    tester,
  ) async {
    late double captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(null, AppTypographyScale.comfortable),
        home: Builder(
          builder: (context) {
            captured = context.uiScale;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(captured, 1.0);
  });
}
