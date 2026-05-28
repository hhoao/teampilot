import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_typography_scale.dart';

/// Central **font family** names and [ThemeExtension] for TeamPilot UI.
///
/// **Font sizes** are configured in [AppTypographyScale] (`app_typography_scale.dart`)
/// — edit `*Base` constants or `standard` / `compact` / `comfortable` multipliers.
///
/// Monospace faces must stay in sync with [loadBundledTerminalFonts] asset paths.
abstract final class AppFonts {
  /// Primary UI sans (CJK + Latin). Runtime: [GoogleFonts.notoSansSc].
  static const String uiGoogleFontName = 'Noto Sans SC';

  /// Bundled terminal / code editor / log viewer face.
  static const String monoFamily = 'JetBrainsMono NFM';

  static const List<String> monoFamilyFallback = [
    'Ubuntu Sans Mono',
    'monospace',
  ];
}

/// Font families attached to [ThemeData.extensions] by [buildLightTheme] /
/// [buildDarkTheme].
@immutable
final class AppFontTheme extends ThemeExtension<AppFontTheme> {
  const AppFontTheme({
    this.uiFontFamily,
    this.uiFontFamilyFallback,
    required this.monoFontFamily,
    required this.monoFontFamilyFallback,
  });

  final String? uiFontFamily;
  final List<String>? uiFontFamilyFallback;
  final String monoFontFamily;
  final List<String> monoFontFamilyFallback;

  static const fallback = AppFontTheme(
    monoFontFamily: AppFonts.monoFamily,
    monoFontFamilyFallback: AppFonts.monoFamilyFallback,
  );

  @override
  AppFontTheme copyWith({
    String? uiFontFamily,
    List<String>? uiFontFamilyFallback,
    String? monoFontFamily,
    List<String>? monoFontFamilyFallback,
  }) {
    return AppFontTheme(
      uiFontFamily: uiFontFamily ?? this.uiFontFamily,
      uiFontFamilyFallback: uiFontFamilyFallback ?? this.uiFontFamilyFallback,
      monoFontFamily: monoFontFamily ?? this.monoFontFamily,
      monoFontFamilyFallback:
          monoFontFamilyFallback ?? this.monoFontFamilyFallback,
    );
  }

  @override
  AppFontTheme lerp(ThemeExtension<AppFontTheme>? other, double t) {
    if (other is! AppFontTheme) return this;
    return t < 0.5 ? this : other;
  }
}

extension AppFontThemeContext on BuildContext {
  AppFontTheme get appFonts =>
      Theme.of(this).extension<AppFontTheme>() ?? AppFontTheme.fallback;
}

/// Monospace [TextStyle] using theme body size unless [fontSize] is set.
TextStyle appMonoTextStyle(
  BuildContext context, {
  TextStyle? base,
  double? fontSize,
  double height = 1.35,
  Color? color,
}) {
  final fonts = context.appFonts;
  final typography = context.appTypography;
  final resolvedBase =
      base ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
  return resolvedBase.copyWith(
    fontFamily: fonts.monoFontFamily,
    fontFamilyFallback: fonts.monoFontFamilyFallback,
    fontSize: fontSize ?? resolvedBase.fontSize ?? typography.mono,
    height: height,
    color: color,
  );
}

/// Builds [TextTheme] with the configured UI sans ([AppFonts.uiGoogleFontName]).
TextTheme buildAppUiTextTheme(TextTheme base) {
  final ui = GoogleFonts.notoSansSc();
  final themed = GoogleFonts.notoSansScTextTheme(base);
  return themed.apply(
    fontFamily: ui.fontFamily,
    fontFamilyFallback: ui.fontFamilyFallback,
  );
}

TextTheme buildAppUiPrimaryTextTheme(TextTheme base) {
  final ui = GoogleFonts.notoSansSc();
  return GoogleFonts.notoSansScTextTheme(base).apply(
    fontFamily: ui.fontFamily,
    fontFamilyFallback: ui.fontFamilyFallback,
  );
}

AppFontTheme buildAppFontTheme({required TextStyle uiFont}) {
  return AppFontTheme(
    uiFontFamily: uiFont.fontFamily,
    uiFontFamilyFallback: uiFont.fontFamilyFallback,
    monoFontFamily: AppFonts.monoFamily,
    monoFontFamilyFallback: AppFonts.monoFamilyFallback,
  );
}
