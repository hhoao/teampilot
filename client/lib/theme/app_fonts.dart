import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_ui/shared_ui.dart';

import 'app_font_resolver.dart';
import 'app_typography_scale.dart';
import 'font_catalog.dart';

export 'app_font_resolver.dart' show AppFontResolver, ResolvedFonts;

/// Central **font family** names for TeamPilot UI.
///
/// **Font sizes** are configured in [AppTypographyScale] (`app_typography_scale.dart`)
/// — edit `*Base` constants or `standard` / `compact` / `comfortable` multipliers.
///
/// Bundled mono catalog family name; active faces come from [ResolvedFonts]
/// via [loadFontsFor]. Platform CJK mono fallbacks are owned by
/// [AppFontResolver]. Families are published on [ThemeData] as [TpFontTheme].
abstract final class AppFonts {
  /// Primary UI sans (CJK + Latin). Runtime: [GoogleFonts.notoSansSc].
  static const String uiGoogleFontName = 'Noto Sans SC';

  /// Bundled JetBrains catalog family (id `jetbrainsMono`), not the active
  /// terminal face when the user prefers `system` or Ubuntu.
  static const String monoFamily = AppFontResolver.bundledMonoFamily;

  /// Mono fallback chain for the bundled [monoFamily]. Delegates to
  /// [AppFontResolver.monoCjkFallback] (Latin faces, then SC before `monospace`).
  static List<String> get monoFamilyFallback =>
      AppFontResolver.monoCjkFallback(defaultTargetPlatform);
}

/// Monospace [TextStyle] using theme body size unless [fontSize] is set.
TextStyle appMonoTextStyle(
  BuildContext context, {
  TextStyle? base,
  double? fontSize,
  double height = 1.35,
  Color? color,
}) {
  final fonts = context.tpFonts;
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

ResolvedFonts _defaultResolvedFonts() => AppFontResolver.resolve(
  uiFontId: FontCatalog.defaultUiId,
  monoFontId: FontCatalog.defaultMonoId,
);

bool _useBundledUiFont(ResolvedFonts fonts) =>
    fonts.uiNeedsBundledLoad || fonts.resolvedUiId == 'notoSansSc';

/// Builds [TextTheme] from [fonts] (defaults to system UI + mono).
///
/// Bundled Noto Sans SC keeps the [GoogleFonts.notoSansScTextTheme] pipeline,
/// then applies [ResolvedFonts] family/fallback. System UI uses [TextTheme.apply]
/// only — no forced Noto.
TextTheme buildAppUiTextTheme(TextTheme base, [ResolvedFonts? fonts]) {
  final resolved = fonts ?? _defaultResolvedFonts();
  if (_useBundledUiFont(resolved)) {
    final themed = GoogleFonts.notoSansScTextTheme(base);
    return themed.apply(
      fontFamily: resolved.uiFamily,
      fontFamilyFallback: resolved.uiFallback,
    );
  }
  return base.apply(
    fontFamily: resolved.uiFamily,
    fontFamilyFallback: resolved.uiFallback,
  );
}

TextTheme buildAppUiPrimaryTextTheme(TextTheme base, [ResolvedFonts? fonts]) {
  final resolved = fonts ?? _defaultResolvedFonts();
  if (_useBundledUiFont(resolved)) {
    return GoogleFonts.notoSansScTextTheme(base).apply(
      fontFamily: resolved.uiFamily,
      fontFamilyFallback: resolved.uiFallback,
    );
  }
  return base.apply(
    fontFamily: resolved.uiFamily,
    fontFamilyFallback: resolved.uiFallback,
  );
}

TpFontTheme buildTpFontTheme(ResolvedFonts fonts) {
  return TpFontTheme(
    uiFontFamily: fonts.uiFamily,
    uiFontFamilyFallback: fonts.uiFallback,
    monoFontFamily: fonts.monoFamily,
    monoFontFamilyFallback: fonts.monoFallback,
  );
}
