import 'dart:io' show Platform;

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _primary = Color(0xFF5B8DEF);
const _secondary = Color(0xFF38CFA2);
const _error = Color(0xFFFF7A7A);

/// Logo 渐变独立于 ThemeMode，作为顶层 const 暴露。
const logoGradientStart = _primary;
const logoGradientEnd = _secondary;

const _subThemes = FlexSubThemesData(
  defaultRadius: 10,
  filledButtonRadius: 999,
  outlinedButtonRadius: 999,
  elevatedButtonRadius: 999,
  inputDecoratorRadius: 8,
  /// 全局使用 [OutlineInputBorder]，避免 FCS 默认的 underline（仅上圆角 + 底边指示线）。
  inputDecoratorBorderType: FlexInputBorderType.outline,
  inputDecoratorIsFilled: true,
  popupMenuRadius: 10,
  popupMenuElevation: 14,
  menuRadius: 10,
  segmentedButtonRadius: 10,
  switchSchemeColor: SchemeColor.primary,
);

/// In `flutter test`, HTTP is stubbed so [google_fonts] cannot download files.
/// Use Material [TextTheme] there; real app loads Noto Sans SC at runtime.
bool _googleFontsNetworkAllowed() {
  try {
    return !Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return true;
  }
}

ThemeData buildLightTheme() => _applyTypography(
  FlexThemeData.light(
    colors: const FlexSchemeColor(
      primary: _primary,
      secondary: _secondary,
      error: _error,
      primaryContainer: _primary,
      secondaryContainer: _secondary,
    ),
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    blendLevel: 7,
    subThemesData: _subThemes,
    useMaterial3: true,
  ),
);

ThemeData buildDarkTheme() => _applyTypography(
  FlexThemeData.dark(
    colors: const FlexSchemeColor(
      primary: _primary,
      secondary: _secondary,
      error: _error,
      primaryContainer: _primary,
      secondaryContainer: _secondary,
    ),
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    blendLevel: 10,
    darkIsTrueBlack: true,
    subThemesData: _subThemes,
    useMaterial3: true,
  ),
);

ThemeData _applyTypography(ThemeData flexTheme) {
  final useRuntimeGoogleFonts = _googleFontsNetworkAllowed();
  if (!useRuntimeGoogleFonts) {
    return flexTheme;
  }
  final typographySeed = ThemeData(
    brightness: flexTheme.brightness,
    colorScheme: flexTheme.colorScheme,
    useMaterial3: true,
  );
  final textTheme = GoogleFonts.notoSansScTextTheme(typographySeed.textTheme);
  final primaryTextTheme =
      GoogleFonts.notoSansScTextTheme(typographySeed.primaryTextTheme);
  final appUiFont = GoogleFonts.notoSansSc();
  return flexTheme.copyWith(
    textTheme: textTheme.apply(
      fontFamily: appUiFont.fontFamily,
      fontFamilyFallback: appUiFont.fontFamilyFallback,
    ),
    primaryTextTheme: primaryTextTheme.apply(
      fontFamily: appUiFont.fontFamily,
      fontFamilyFallback: appUiFont.fontFamilyFallback,
    ),
  );
}
