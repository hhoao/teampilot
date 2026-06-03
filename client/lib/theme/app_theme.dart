import 'dart:io' show Platform;

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_fonts.dart';
import 'app_icon_sizes.dart';
import 'app_outline_input_theme.dart';
import 'app_typography_scale.dart';

/// Persisted preset ids (order = settings UI order).
const List<String> kThemeColorPresetIds = [
  'graphite',
  'ocean',
  'violet',
  'amber',
  'forest',
];

const String kDefaultThemeColorPreset = 'amber';

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
  // primaryContainer == primary in our palettes; default M3 hover thumb
  // would match the track. Keep thumb on onPrimary for contrast.
  switchThumbSchemeColor: SchemeColor.onPrimary,
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

ThemeData buildLightTheme([
  String? themeColorPreset,
  AppTypographyScale typographyScale = AppTypographyScale.standard,
]) => _applyTypography(
  FlexThemeData.light(
    colors: _flexSchemeColors(normalizeThemeColorPreset(themeColorPreset)),
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,

    /// Higher blend: scaffold / cards pick up more of the seed colors so
    /// presets change the whole UI, not only primary-filled controls.
    blendLevel: 30,
    subThemesData: _subThemes,
    useMaterial3: true,
  ),
  typographyScale: typographyScale,
);

ThemeData buildDarkTheme([
  String? themeColorPreset,
  AppTypographyScale typographyScale = AppTypographyScale.standard,
]) => _applyTypography(
  FlexThemeData.dark(
    colors: _flexSchemeColors(normalizeThemeColorPreset(themeColorPreset)),
    surfaceMode: FlexSurfaceMode.highScaffoldLevelSurface,
    blendLevel: 30,

    /// When true, base layer stays near #000 so only upper surfaces show
    /// strong tint. Set false for a fully tinted dark scaffold (tradeoff:
    /// less OLED “true black”).
    darkIsTrueBlack: true,
    subThemesData: _subThemes,
    useMaterial3: true,
  ),
  typographyScale: typographyScale,
);

ThemeData _applyTypography(
  ThemeData flexTheme, {
  AppTypographyScale typographyScale = AppTypographyScale.standard,
}) {
  final typographyTheme = AppTypographyTheme.fromScale(typographyScale);
  final useRuntimeGoogleFonts = _googleFontsNetworkAllowed();
  final compactOutlinedButton = OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      minimumSize: const Size(64, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );

  if (!useRuntimeGoogleFonts) {
    // Tests: Flex [TextTheme] may omit explicit font sizes; Material seed has them.
    final seed = ThemeData(
      brightness: flexTheme.brightness,
      colorScheme: flexTheme.colorScheme,
      useMaterial3: true,
    );
    final textTheme = applyAppInputTextStyles(
      materializeM3TextThemeSizes(seed.textTheme, scale: typographyScale),
    );
    return flexTheme.copyWith(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      iconTheme: AppIconSizes.iconTheme(),
      textTheme: textTheme,
      extensions: [AppFontTheme.fallback, typographyTheme],
      inputDecorationTheme: buildAppOutlineInputDecorationTheme(
        colorScheme: flexTheme.colorScheme,
        textTheme: textTheme,
      ),
      outlinedButtonTheme: compactOutlinedButton,
    );
  }
  final typographySeed = ThemeData(
    brightness: flexTheme.brightness,
    colorScheme: flexTheme.colorScheme,
    useMaterial3: true,
  );
  final textTheme = buildAppUiTextTheme(typographySeed.textTheme);
  final primaryTextTheme = buildAppUiPrimaryTextTheme(
    typographySeed.primaryTextTheme,
  );
  final appUiFont = GoogleFonts.notoSansSc();
  final mergedTextTheme = applyAppInputTextStyles(
    materializeM3TextThemeSizes(textTheme, scale: typographyScale),
  );

  return flexTheme.copyWith(
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    iconTheme: AppIconSizes.iconTheme(),
    textTheme: mergedTextTheme,
    primaryTextTheme: primaryTextTheme,
    extensions: [
      buildAppFontTheme(uiFont: appUiFont),
      typographyTheme,
    ],
    inputDecorationTheme: buildAppOutlineInputDecorationTheme(
      colorScheme: flexTheme.colorScheme,
      textTheme: mergedTextTheme,
    ),
    outlinedButtonTheme: compactOutlinedButton,
  );
}
