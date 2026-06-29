import 'package:flutter/material.dart';

import 'app_fonts.dart';
import 'app_outline_input_theme.dart';
import 'app_text_styles.dart';

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

/// Semantic [TextStyle]s to shape against [warmupGlyphs] at boot — the same
/// variants the UI uses ([AppTextStyles], inputs, dropdowns), not widget literals.
List<TextStyle> textStylesForInteractiveWarmup() {
  final theme = bootstrapThemeForTextWarmup();
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
