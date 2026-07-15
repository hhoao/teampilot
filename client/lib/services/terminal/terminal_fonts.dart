import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:teampilot/theme/app_fonts.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:shared_ui/shared_ui.dart';

/// Bundled JetBrains catalog family name (not necessarily the active terminal
/// face — that comes from [TpFontTheme] / [appTerminalTextStyle]).
const kTerminalFontFamily = AppFonts.monoFamily;

/// Bundled alternate mono catalog family; may appear in mono fallbacks.
const kUbuntuSansMonoFontFamily = 'Ubuntu Sans Mono';

/// Terminal face + size from [AppTypographyTheme.terminal].
///
/// The terminal renders via [TerminalView] (a [CustomPaint], not a [Text]
/// widget), so it never picks up [MediaQuery.textScaler]. Density now comes from
/// the app-owned UI scale baked into [AppTypographyTheme.terminal]
/// (= terminalBase * uiScale), so the terminal scales with the rest of the UI
/// without any OS-textScaler dependence. The size drives both cell metrics and
/// glyph rendering, so columns stay aligned.
TerminalStyle appTerminalTextStyle(BuildContext context) {
  final typography = context.appTypography;
  final fonts = context.tpFonts;
  return TerminalStyle(
    size: typography.terminal,
    family: fonts.monoFontFamily,
    lineHeight: 1.3,
    fallback: fonts.monoFontFamilyFallback,
  );
}
