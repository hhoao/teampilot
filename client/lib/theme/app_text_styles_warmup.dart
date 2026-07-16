import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../models/layout_preferences.dart';
import 'app_fonts.dart';
import 'app_markdown_style_sheet.dart';
import 'app_outline_input_theme.dart';
import 'app_typography_scale.dart';
import 'font_catalog.dart';

ResolvedFonts _fontsFromPreferences(LayoutPreferences? preferences) {
  return AppFontResolver.resolve(
    uiFontId: preferences?.uiFontId ?? FontCatalog.defaultUiId,
    monoFontId: preferences?.monoFontId ?? FontCatalog.defaultMonoId,
  );
}

/// Bootstrap theme matching production text pipeline (standard scale, light).
ThemeData bootstrapThemeForTextWarmup([ResolvedFonts? fonts]) {
  final resolved = fonts ?? _fontsFromPreferences(null);
  final seed = ThemeData(brightness: Brightness.light, useMaterial3: true);
  final control = TpControlMetrics.fromScale(AppTypographyScale.standard.multiplier);
  final textTheme = applyAppInputTextStyles(
    materializeM3TextThemeSizes(buildAppUiTextTheme(seed.textTheme, resolved)),
  );
  return seed.copyWith(
    textTheme: textTheme,
    extensions: [buildTpFontTheme(resolved)],
    inputDecorationTheme: buildAppOutlineInputDecorationTheme(
      colorScheme: seed.colorScheme,
      textTheme: textTheme,
      control: control,
    ),
  );
}

/// User typography on the bootstrap font pipeline — avoids building full
/// [buildLightTheme] / [buildDarkTheme] during the boot gate (those pull in
/// Google Fonts and FlexColorScheme and can stall startup for a long time).
ThemeData themeForInteractiveWarmup(LayoutPreferences preferences) {
  final fonts = _fontsFromPreferences(preferences);
  final textBaseline = _systemTextBaseline();
  final effectiveTextMult = resolveRelativeScale(
    scaleId: normalizeTypographyScale(preferences.typographyScale),
    customMultiplier: preferences.typographyScaleCustomMultiplier,
    baseline: textBaseline,
  );
  final textScale = AppTypographyScale(multiplier: effectiveTextMult);
  final seed = bootstrapThemeForTextWarmup(fonts);
  final control = TpControlMetrics.fromScale(textScale.multiplier);
  final textTheme = applyAppInputTextStyles(
    materializeM3TextThemeSizes(seed.textTheme, scale: textScale),
  );
  return seed.copyWith(
    textTheme: textTheme,
    extensions: [buildTpFontTheme(fonts)],
    inputDecorationTheme: buildAppOutlineInputDecorationTheme(
      colorScheme: seed.colorScheme,
      textTheme: textTheme,
      control: control,
    ),
  );
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

List<TextStyle> _hostExtraWarmupStyles(ThemeData theme) {
  final textTheme = theme.textTheme;
  final fonts = theme.extension<TpFontTheme>() ?? TpFontTheme.fallback;
  final inputTheme = theme.inputDecorationTheme;
  final bodyMedium = textTheme.bodyMedium ?? const TextStyle();
  final labelLarge = textTheme.labelLarge ?? bodyMedium;

  TextStyle withUi(TextStyle style) => style.copyWith(
    fontFamily: fonts.uiFontFamily,
    fontFamilyFallback: fonts.uiFontFamilyFallback,
  );

  final hint = inputTheme.hintStyle;
  return [
    if (hint != null) withUi(hint),
    withUi(appTextFieldStyle(textTheme)),
    withUi(bodyMedium.copyWith(fontWeight: FontWeight.w500, height: 1.25)),
    withUi(bodyMedium.copyWith(fontWeight: FontWeight.w400, height: 1.25)),
    withUi(labelLarge),
  ];
}

/// All [TextStyle]s shaped at boot for [theme] (UI + host extras + markdown).
List<TextStyle> textStylesForThemeWarmup(ThemeData theme) {
  return [
    ...TpTextStyles(theme).stylesForWarmup(),
    ..._hostExtraWarmupStyles(theme),
    ...appMarkdownTextStyles(theme),
  ];
}

/// Semantic [TextStyle]s to shape against host glyphs at boot.
List<TextStyle> textStylesForInteractiveWarmup({
  LayoutPreferences? preferences,
}) {
  final theme = preferences == null
      ? bootstrapThemeForTextWarmup()
      : themeForInteractiveWarmup(preferences);
  return TpGlyphWarmup.dedupeByShapeKey(textStylesForThemeWarmup(theme));
}
