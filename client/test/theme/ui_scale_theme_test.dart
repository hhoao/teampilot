import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
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

  test('tooltip text style scales with the text-size scale', () {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);

    expect(
      comfy.tooltipTheme.textStyle!.fontSize!,
      greaterThan(std.tooltipTheme.textStyle!.fontSize!),
    );
    expect(
      comfy.tooltipTheme.textStyle!.fontSize,
      comfy.textTheme.bodyMedium!.fontSize,
    );
  });

  test('list tile subtitle style scales with the text-size scale', () {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);

    expect(
      comfy.listTileTheme.subtitleTextStyle!.fontSize!,
      greaterThan(std.listTileTheme.subtitleTextStyle!.fontSize!),
    );
    expect(std.listTileTheme.dense, isFalse);
  });

  testWidgets('ListTile subtitle uses theme size, not dense 12px override', (
    tester,
  ) async {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);

    Future<double> subtitleFontSize(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(theme.listTileTheme.subtitleTextStyle?.fontSize),
          theme: theme,
          home: const Scaffold(
            body: ListTile(
              title: Text('Title'),
              subtitle: Text('Subtitle'),
            ),
          ),
        ),
      );
      return DefaultTextStyle.of(tester.element(find.text('Subtitle'))).style
          .fontSize!;
    }

    final stdSize = await subtitleFontSize(std);
    final comfySize = await subtitleFontSize(comfy);
    expect(comfySize, greaterThan(stdSize));
    expect(stdSize, std.listTileTheme.subtitleTextStyle!.fontSize);
    expect(comfySize, comfy.listTileTheme.subtitleTextStyle!.fontSize);
  });

  test('spacing tokens are fixed (independent of the text-size scale)', () {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);

    // Text size scales fonts only; padding does not follow it (the whole-UI
    // UiZoom is the knob that scales spacing).
    expect(std.extension<AppSpacingTheme>()!.md, AppSpacingTheme.mdBase);
    expect(comfy.extension<AppSpacingTheme>()!.md, AppSpacingTheme.mdBase);
  });

  test('icon theme scales with the text-size preset (mapped, not 1:1)', () {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);

    final stdIconMult = AppIconSizes.resolveIconMultiplier(
      effectiveTextMultiplier: 1.0,
      textBaseline: 1.0,
    );
    expect(std.iconTheme.size, AppIconSizes.mdBase * stdIconMult);
    expect(
      comfy.iconTheme.size,
      greaterThan(std.iconTheme.size!),
    );
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
