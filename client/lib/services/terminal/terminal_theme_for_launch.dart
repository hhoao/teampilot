import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../models/layout_preferences.dart';
import '../../theme/app_theme.dart';
import '../../theme/workspace_surface_layers.dart';
import 'terminal_session.dart';
import 'terminal_theme_mapper.dart';

/// Resolves the embedded terminal theme from layout prefs (no BuildContext).
///
/// Used at member PTY connect so background shells get the same COLORFGBG as
/// the foreground workbench terminal — Claude `theme: auto` reads that env at
/// startup.
TerminalTheme resolveTerminalThemeFromLayout({
  required LayoutPreferences preferences,
  required Brightness platformBrightness,
}) {
  final isDark = switch (preferences.themeMode) {
    'light' => false,
    'dark' => true,
    _ => platformBrightness == Brightness.dark,
  };
  final colorScheme = isDark
      ? buildDarkTheme(preferences.themeColorPreset).colorScheme
      : buildLightTheme(preferences.themeColorPreset).colorScheme;
  return teampilotTerminalTheme(
    colorScheme,
    isDark: isDark,
    mode: preferences.terminalThemeMode,
    chrome: WorkspacePageChrome.workspace,
  );
}

/// Applies [theme] to [shell] before [TerminalSession.connect] so PTY spawn
/// advertises the correct COLORFGBG.
void applyShellTerminalThemeForLaunch(TerminalSession shell, TerminalTheme theme) {
  shell.applyTerminalTheme(theme);
}
