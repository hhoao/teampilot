import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:teampilot/theme/app_fonts.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/logger.dart';

/// Active terminal font ([TerminalStyle.family]).
const kTerminalFontFamily = AppFonts.monoFamily;

/// Bundled alternate; listed in [TerminalStyle.fallback].
const kUbuntuSansMonoFontFamily = 'Ubuntu Sans Mono';

/// Terminal face + size from [AppTypographyTheme.terminal].
///
/// The terminal renders via [TerminalView] (a [CustomPaint], not a [Text]
/// widget), so it never picks up [MediaQuery.textScaler] automatically the way
/// the rest of the UI does. On Linux the GTK embedder feeds the GNOME
/// `text-scaling-factor` into [MediaQuery.textScaler], so without applying it
/// here the terminal stays at the raw 14px while every other surface grows —
/// making the terminal look smaller. Scaling the [TerminalStyle.size] keeps the
/// terminal in step (the size drives both cell metrics and glyph rendering, so
/// columns stay aligned).
TerminalStyle appTerminalTextStyle(BuildContext context) {
  final typography = context.appTypography;
  final fonts = context.appFonts;
  final textScaler = MediaQuery.textScalerOf(context);
  return TerminalStyle(
    size: textScaler.scale(typography.terminal),
    family: fonts.monoFontFamily,
    lineHeight: 1.3,
    fallback: fonts.monoFontFamilyFallback,
  );
}

/// Loads terminal fonts from [assets/fonts/terminal/] (see sync script).
///
/// JetBrainsMono NFM is the default face. Ubuntu Sans Mono is preloaded for
/// fallback / future switching (change [kTerminalFontFamily] + Regular asset).
Future<void> _loadFontAsset(FontLoader loader, String assetPath) async {
  try {
    loader.addFont(rootBundle.load(assetPath));
    await loader.load();
  } on Object {
    appLogger.w('Failed to load font asset: $assetPath');
  }
}

Future<void> loadBundledTerminalFonts() async {
  await _loadFontAsset(
    FontLoader(kTerminalFontFamily),
    'assets/fonts/terminal/JetBrainsMonoNerdFontMono-Regular.ttf',
  );

  final ubuntu = FontLoader(kUbuntuSansMonoFontFamily);
  var hasUbuntuFont = false;
  for (final asset in const [
    'assets/fonts/terminal/UbuntuSansMono-Regular.ttf',
    'assets/fonts/terminal/UbuntuSansMono-Bold.ttf',
  ]) {
    try {
      ubuntu.addFont(rootBundle.load(asset));
      hasUbuntuFont = true;
    } on Object {
      appLogger.w('Failed to load Ubuntu font asset: $asset');
    }
  }
  if (!hasUbuntuFont) return;
  try {
    await ubuntu.load();
  } on Object {
    // No Ubuntu files in bundle; terminal uses JetBrains or system monospace.
  }
}
