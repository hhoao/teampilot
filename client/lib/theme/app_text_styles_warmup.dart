import 'package:flutter/material.dart';

import '../models/layout_preferences.dart';
import 'app_control_theme.dart';
import 'app_fonts.dart';
import 'app_markdown_style_sheet.dart';
import 'app_outline_input_theme.dart';
import 'app_text_styles.dart';
import 'app_typography_scale.dart';
import 'font_catalog.dart';

ResolvedFonts _fontsFromPreferences(LayoutPreferences? preferences) {
  return AppFontResolver.resolve(
    uiFontId: preferences?.uiFontId ?? FontCatalog.systemId,
    monoFontId: preferences?.monoFontId ?? FontCatalog.systemId,
  );
}

/// Bootstrap theme matching production text pipeline (standard scale, light).
ThemeData bootstrapThemeForTextWarmup([ResolvedFonts? fonts]) {
  final resolved = fonts ?? _fontsFromPreferences(null);
  final seed = ThemeData(brightness: Brightness.light, useMaterial3: true);
  final control = AppControlTheme.fromScale(AppTypographyScale.standard);
  final textTheme = applyAppInputTextStyles(
    materializeM3TextThemeSizes(buildAppUiTextTheme(seed.textTheme, resolved)),
  );
  return seed.copyWith(
    textTheme: textTheme,
    extensions: [buildAppFontTheme(resolved), control],
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
  final textTheme = applyAppInputTextStyles(
    materializeM3TextThemeSizes(seed.textTheme, scale: textScale),
  );
  return seed.copyWith(
    textTheme: textTheme,
    extensions: [
      buildAppFontTheme(fonts),
      AppControlTheme.fromScale(textScale),
    ],
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

List<TextStyle> _appUiTextStylesFromTheme(ThemeData theme) {
  final styles = AppTextStyles(theme);
  final textTheme = theme.textTheme;
  final scheme = theme.colorScheme;
  final fonts = theme.extension<AppFontTheme>() ?? AppFontTheme.fallback;
  final control =
      theme.extension<AppControlTheme>() ??
      AppControlTheme.fromScale(AppTypographyScale.standard);
  final inputTheme = buildAppOutlineInputDecorationTheme(
    colorScheme: scheme,
    textTheme: textTheme,
    control: control,
  );
  final bodyMedium = textTheme.bodyMedium ?? const TextStyle();
  final labelLarge = textTheme.labelLarge ?? bodyMedium;

  TextStyle withUi(TextStyle style) => style.copyWith(
    fontFamily: fonts.uiFontFamily,
    fontFamilyFallback: fonts.uiFontFamilyFallback,
  );

  return [
    withUi(styles.xs),
    withUi(styles.xsMedium),
    withUi(styles.xsSemibold),
    withUi(styles.xsBold),
    withUi(styles.xsSemiboldSnug),
    withUi(styles.xsBoldWide),
    withUi(styles.xsTrack),
    withUi(styles.sm),
    withUi(styles.smMedium),
    withUi(styles.smSemibold),
    withUi(styles.smBold),
    withUi(styles.smSemiboldTrack),
    withUi(styles.md),
    withUi(styles.mdSnug),
    withUi(styles.mdMedium),
    withUi(styles.mdMediumSnug),
    withUi(styles.mdSemibold),
    withUi(styles.mdBold),
    withUi(styles.mdRelaxed),
    withUi(styles.mdSemiboldTightSnug),
    withUi(styles.mdBoldSpread),
    withUi(styles.lg),
    withUi(styles.lgMedium),
    withUi(styles.lgSemibold),
    withUi(styles.lgBold),
    withUi(styles.lgSnug),
    withUi(styles.lgBoldSnug),
    withUi(styles.lgSemiboldSnug),
    withUi(styles.xl),
    withUi(styles.display),
    withUi(styles.mutedXs),
    withUi(styles.mutedSm),
    withUi(styles.mutedMd),
    withUi(appTextFieldStyle(textTheme)),
    withUi(inputTheme.hintStyle!),
    withUi(bodyMedium.copyWith(fontWeight: FontWeight.w500, height: 1.25)),
    withUi(bodyMedium.copyWith(fontWeight: FontWeight.w400, height: 1.25)),
    styles.mono.copyWith(
      fontFamily: fonts.monoFontFamily,
      fontFamilyFallback: fonts.monoFontFamilyFallback,
    ),
    withUi(labelLarge),
    // md + italic — markdown `em` (and any italic body copy)
    withUi(styles.md.copyWith(fontStyle: FontStyle.italic)),
    withUi(styles.md.copyWith(decoration: TextDecoration.lineThrough)),
  ];
}

/// All [TextStyle]s shaped at boot for [theme] (UI + markdown).
List<TextStyle> textStylesForThemeWarmup(ThemeData theme) {
  return [
    ..._appUiTextStylesFromTheme(theme),
    ...appMarkdownTextStyles(theme),
  ];
}

/// Semantic [TextStyle]s to shape against [warmupGlyphs] at boot — the same
/// variants the UI uses ([AppTextStyles], inputs, dropdowns, markdown), not
/// widget literals.
List<TextStyle> textStylesForInteractiveWarmup({
  LayoutPreferences? preferences,
}) {
  final theme = preferences == null
      ? bootstrapThemeForTextWarmup()
      : themeForInteractiveWarmup(preferences);
  return textStylesForThemeWarmup(theme);
}
