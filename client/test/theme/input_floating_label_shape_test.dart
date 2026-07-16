import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_font_resolver.dart';
import 'package:teampilot/theme/app_fonts.dart';
import 'package:teampilot/theme/app_outline_input_theme.dart';
import 'package:teampilot/theme/app_text_styles_warmup.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/theme/font_catalog.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  late TextTheme textTheme;
  late InputDecorationThemeData inputTheme;

  setUp(() {
    final fonts = AppFontResolver.resolve(
      uiFontId: FontCatalog.defaultUiId,
      monoFontId: FontCatalog.defaultMonoId,
    );
    final seed = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    final control = TpControlMetrics.fromScale(
      AppTypographyScale.standard.multiplier,
    );
    textTheme = applyAppInputTextStyles(
      materializeM3TextThemeSizes(buildAppUiTextTheme(seed.textTheme, fonts)),
    );
    inputTheme = buildAppOutlineInputDecorationTheme(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4),
        brightness: Brightness.dark,
      ),
      textTheme: textTheme,
      control: control,
    );
  });

  /// Mirrors [InputDecorator] `_getInlineLabelStyle` / `_getFloatingLabelStyle`.
  TextStyle decoratorLabelStyle(TextStyle? decorationStyle) {
    return textTheme.titleMedium!.merge(decorationStyle).copyWith(height: 1);
  }

  test(
    'floating label keeps the same shape fingerprint as the inline label',
    () {
      // Focus runs AnimatedDefaultTextStyle(label → floating). Any change to
      // family / size / weight forces RenderParagraph to reshape CJK (Noto
      // Sans SC) on the UI thread and stalls the float animation (~1s).
      final inline = decoratorLabelStyle(inputTheme.labelStyle);
      final floating = decoratorLabelStyle(inputTheme.floatingLabelStyle);

      expect(
        TpGlyphWarmup.shapeKey(floating),
        TpGlyphWarmup.shapeKey(inline),
        reason:
            'floatingLabelStyle must differ from labelStyle by color only, '
            'not by layout-affecting fields',
      );
    },
  );
}
