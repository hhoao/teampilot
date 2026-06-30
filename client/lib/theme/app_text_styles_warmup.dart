import 'package:flutter/material.dart';

import '../models/layout_preferences.dart';
import 'app_fonts.dart';
import 'app_outline_input_theme.dart';
import 'app_text_styles.dart';
import 'app_typography_scale.dart';

/// Bootstrap theme matching production text pipeline (standard scale, light).
ThemeData bootstrapThemeForTextWarmup() {
  final seed = ThemeData(brightness: Brightness.light, useMaterial3: true);
  final textTheme = applyAppInputTextStyles(
    materializeM3TextThemeSizes(buildAppUiTextTheme(seed.textTheme)),
  );
  return seed.copyWith(
    textTheme: textTheme,
    extensions: [AppFontTheme.fallback],
  );
}

/// User typography on the bootstrap font pipeline — avoids building full
/// [buildLightTheme] / [buildDarkTheme] during the boot gate (those pull in
/// Google Fonts and FlexColorScheme and can stall startup for a long time).
ThemeData themeForInteractiveWarmup(LayoutPreferences preferences) {
  final textBaseline = _systemTextBaseline();
  final effectiveTextMult = resolveRelativeScale(
    scaleId: normalizeTypographyScale(preferences.typographyScale),
    customMultiplier: preferences.typographyScaleCustomMultiplier,
    baseline: textBaseline,
  );
  final textScale = AppTypographyScale(multiplier: effectiveTextMult);
  final seed = bootstrapThemeForTextWarmup();
  final textTheme = applyAppInputTextStyles(
    materializeM3TextThemeSizes(seed.textTheme, scale: textScale),
  );
  return seed.copyWith(textTheme: textTheme);
}

double _systemTextBaseline() {
  final systemView = WidgetsBinding.instance.platformDispatcher.implicitView;
  final systemMq = systemView == null
      ? const MediaQueryData()
      : MediaQueryData.fromView(systemView);
  return autoTextScaleForSystem(
    systemMq.textScaler.scale(1.0),
    systemMq.devicePixelRatio,
  );
}

List<TextStyle> _textStylesFromTheme(ThemeData theme) {
  final styles = AppTextStyles(theme);
  final textTheme = theme.textTheme;
  final scheme = theme.colorScheme;
  final inputTheme = buildAppOutlineInputDecorationTheme(
    colorScheme: scheme,
    textTheme: textTheme,
  );
  final bodyMedium = textTheme.bodyMedium ?? const TextStyle();
  final labelLarge = textTheme.labelLarge ?? bodyMedium;

  return [
    styles.caption,
    styles.toolPanelTitle,
    styles.settingsGroupHeader,
    styles.bodySmall,
    styles.body,
    styles.bodyStrong,
    styles.prominent,
    styles.prominent.copyWith(fontWeight: FontWeight.w500),
    styles.prominent.copyWith(fontWeight: FontWeight.w600),
    styles.sectionTitle,
    styles.subtitle,
    styles.dialogTitle,
    styles.fileTreeRootLabel(scheme.onSurface),
    styles.fileTreeEntryLabel(color: scheme.onSurface, active: false),
    styles.fileTreeEntryLabel(color: scheme.onSurface, active: true),
    appTextFieldStyle(textTheme),
    inputTheme.hintStyle!,
    bodyMedium.copyWith(fontWeight: FontWeight.w500, height: 1.25),
    bodyMedium.copyWith(fontWeight: FontWeight.w400, height: 1.25),
    styles.mono,
    labelLarge,
  ];
}

/// Semantic [TextStyle]s to shape against [warmupGlyphs] at boot — the same
/// variants the UI uses ([AppTextStyles], inputs, dropdowns), not widget literals.
List<TextStyle> textStylesForInteractiveWarmup({
  LayoutPreferences? preferences,
}) {
  final theme = preferences == null
      ? bootstrapThemeForTextWarmup()
      : themeForInteractiveWarmup(preferences);
  return _textStylesFromTheme(theme);
}
