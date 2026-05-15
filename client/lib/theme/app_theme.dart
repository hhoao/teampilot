import 'dart:io' show Platform;

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Persisted preset ids (order = settings UI order).
const List<String> kThemeColorPresetIds = [
  'graphite',
  'ocean',
  'violet',
  'amber',
  'forest',
];

const String kDefaultThemeColorPreset = 'graphite';

String normalizeThemeColorPreset(String? raw) {
  if (raw != null && kThemeColorPresetIds.contains(raw)) return raw;
  return kDefaultThemeColorPreset;
}

typedef _Palette = ({
  Color primary,
  Color secondary,
  Color error,
  /// When set, used for logo gradient only; [primary] is the interactive seed
  /// for [ColorScheme] (outlines, links, filled buttons).
  Color? logoPrimary,
});

const _palettes = <String, _Palette>{
  'graphite': (
    /// Mid cool gray so controls contrast on near-black dark surfaces; the
    /// near-black [#2E3033] is reserved for [logoPrimary] only.
    primary: Color(0xFF8B939E),
    secondary: Color(0xFF38CFA2),
    error: Color(0xFFFF7A7A),
    logoPrimary: Color(0xFF2E3033),
  ),
  'ocean': (
    primary: Color(0xFF6A90B8),
    secondary: Color(0xFF72A8A8),
    error: Color(0xFFD87A7A),
    logoPrimary: null,
  ),
  'violet': (
    primary: Color(0xFF9B8FC9),
    secondary: Color(0xFFB5A3D4),
    error: Color(0xFFD87A7A),
    logoPrimary: null,
  ),
  'amber': (
    primary: Color(0xFFD4A06A),
    secondary: Color(0xFFE4C080),
    error: Color(0xFFD8897A),
    logoPrimary: null,
  ),
  'forest': (
    primary: Color(0xFF7FA892),
    secondary: Color(0xFF9CB89E),
    error: Color(0xFFD88A8A),
    logoPrimary: null,
  ),
};

_Palette _palette(String presetId) =>
    _palettes[normalizeThemeColorPreset(presetId)]!;

/// Seeds the Material [ColorScheme]. Flex Color Scheme also blends
/// [primary]/[secondary] into surfaces per [surfaceMode] and [blendLevel]
/// (not only buttons).
FlexSchemeColor _flexSchemeColors(String presetId) {
  final p = _palette(presetId);
  return FlexSchemeColor(
    primary: p.primary,
    secondary: p.secondary,
    error: p.error,
    primaryContainer: p.primary,
    secondaryContainer: p.secondary,
  );
}

/// Primary accent for branding (e.g. logo gradient) for the given preset.
Color logoGradientStartFor(String presetId) {
  final p = _palette(presetId);
  return p.logoPrimary ?? p.primary;
}

/// Secondary accent for branding for the given preset.
Color logoGradientEndFor(String presetId) => _palette(presetId).secondary;

Color themePresetSwatchPrimary(String presetId) => _palette(presetId).primary;

Color themePresetSwatchSecondary(String presetId) =>
    _palette(presetId).secondary;

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

ThemeData buildLightTheme([String? themeColorPreset]) => _applyTypography(
  FlexThemeData.light(
    colors: _flexSchemeColors(normalizeThemeColorPreset(themeColorPreset)),
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,

    /// Higher blend: scaffold / cards pick up more of the seed colors so
    /// presets change the whole UI, not only primary-filled controls.
    blendLevel: 12,
    subThemesData: _subThemes,
    useMaterial3: true,
  ),
);

ThemeData buildDarkTheme([String? themeColorPreset]) => _applyTypography(
  FlexThemeData.dark(
    colors: _flexSchemeColors(normalizeThemeColorPreset(themeColorPreset)),
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    blendLevel: 40,

    /// When true, base layer stays near #000 so only upper surfaces show
    /// strong tint. Set false for a fully tinted dark scaffold (tradeoff:
    /// less OLED “true black”).
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
  final primaryTextTheme = GoogleFonts.notoSansScTextTheme(
    typographySeed.primaryTextTheme,
  );
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
