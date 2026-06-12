import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_spacing.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('theme carries AppSpacingTheme that scales with typography scale', () {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);

    final stdSpacing = std.extension<AppSpacingTheme>();
    final comfySpacing = comfy.extension<AppSpacingTheme>();

    expect(stdSpacing, isNotNull);
    expect(stdSpacing!.md, AppSpacingTheme.mdBase);
    expect(comfySpacing!.md, greaterThan(stdSpacing.md));
    expect(comfySpacing.scale, AppTypographyScale.comfortable.multiplier);
  });

  testWidgets('context.uiScale reflects the active theme scale', (tester) async {
    late double captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(null, AppTypographyScale.compact),
        home: Builder(
          builder: (context) {
            captured = context.uiScale;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(captured, AppTypographyScale.compact.multiplier);
  });
}
