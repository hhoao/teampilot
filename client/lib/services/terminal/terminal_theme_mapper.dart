import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

int _packColor(Color color) => color.toARGB32() & 0xFFFFFF;

/// OSC 8 hyperlink highlight (rendered via [TerminalTheme.hintStart]).
({int bg, int fg}) _hyperlinkHintFromScheme(ColorScheme cs) =>
    (bg: _packColor(cs.primary), fg: _packColor(cs.onPrimary));

/// Maps [TerminalTheme] into engine [TerminalColors] (PTY palette + defaults).
TerminalColors terminalColorsFromTheme(TerminalTheme theme) {
  return TerminalColors(
    background: theme.background,
    foreground: theme.foreground,
    selection: theme.selection,
    ansi: List<int>.from(theme.ansi),
    searchMatchBg: theme.searchMatch.bg,
    searchMatchFg: theme.searchMatch.fg,
    searchFocusedBg: theme.searchFocused.bg,
    searchFocusedFg: theme.searchFocused.fg,
    hintStartFg: theme.hintStart.fg,
    hintStartBg: theme.hintStart.bg,
    cursorText: theme.cursorText,
    cursorBody: theme.cursorColor,
  );
}

/// TeamPilot terminal config: theme colors + scrollback, other fields from defaults.
TerminalConfig terminalConfigFromTheme(
  TerminalTheme theme, {
  int scrollbackLines = 10000,
}) {
  return TerminalConfig.defaults().copyWith(
    colors: terminalColorsFromTheme(theme),
    scrolling: TerminalConfig.defaults().scrolling.copyWith(
      history: scrollbackLines,
    ),
    cursor: CursorConfig(
      blinkInterval: 750,
      defaultShape: 0,
      defaultBlinking: true,
      blinkTimeout: 0,
    ),
  );
}

/// Fingerprint for skipping redundant [TerminalEngine.reconfigure] calls.
int terminalThemeFingerprint(TerminalTheme theme) => Object.hash(
  theme.background,
  theme.foreground,
  theme.selection,
  Object.hashAll(theme.ansi),
  theme.searchMatch.bg,
  theme.searchMatch.fg,
  theme.searchFocused.bg,
  theme.searchFocused.fg,
  theme.hintStart.bg,
  theme.hintStart.fg,
  theme.cursorText,
  theme.cursorColor,
  theme.bellOverlay,
);

/// Maps TeamPilot layout theme modes to [TerminalTheme] (packed RGB).
TerminalTheme teampilotTerminalTheme(
  ColorScheme cs, {
  required bool isDark,
  required String mode,
}) {
  if (mode == 'classicDark') {
    return TerminalTheme(
      background: 0x0A0C10,
      foreground: 0xC8CCD4,
      selection: 0x9AA0A8,
      ansi: const [
        0x1A1A1A,
        0xD04A62,
        0x52C07E,
        0xD4B85A,
        0x5298D8,
        0xB87CD8,
        0x4EB8C4,
        0xD0D4DC,
        0x5A5A5A,
        0xE86A7E,
        0x6CD898,
        0xE8CC70,
        0x72B0E8,
        0xD098F0,
        0x72D0DC,
        0xE4E6EC,
      ],
      searchMatch: (bg: 0xFFFF2B, fg: 0x000000),
      searchFocused: (bg: 0x31FF26, fg: 0x000000),
      hintStart: (bg: 0x5298D8, fg: 0x0A0C10),
      cursorText: null,
      cursorColor: 0x9AA0A8,
      bellOverlay: 0xFFFFFF,
    );
  }

  if (mode == 'highContrast') {
    final bg = isDark ? 0x000000 : 0xFFFFFF;
    final fg = isDark ? 0xF5F7FA : 0x111111;
    final primary = isDark ? 0x69B3FF : 0x005FCC;
    final secondary = isDark ? 0x4EE2A8 : 0x007A4B;
    return TerminalTheme(
      background: bg,
      foreground: fg,
      selection: primary,
      ansi: [
        isDark ? 0x1A1A1A : 0x2A2A2A,
        isDark ? 0xFF6B7A : 0xB00020,
        secondary,
        isDark ? 0xFFD166 : 0x8A6D00,
        primary,
        isDark ? 0xD79BFF : 0x7A3DB8,
        isDark ? 0x63E6FF : 0x006A85,
        fg,
        isDark ? 0x8C8C8C : 0x666666,
        isDark ? 0xFF98A3 : 0xD32F2F,
        isDark ? 0x8AF0C6 : 0x0A8F5A,
        isDark ? 0xFFE08A : 0xA88700,
        isDark ? 0x9CCEFF : 0x1976D2,
        isDark ? 0xE7C0FF : 0x9C4DCC,
        isDark ? 0x9CEEFF : 0x008DB3,
        isDark ? 0xFFFFFF : 0x000000,
      ],
      searchMatch: (bg: 0xFFFF2B, fg: 0x000000),
      searchFocused: (bg: 0x31FF26, fg: 0x000000),
      hintStart: (bg: primary, fg: isDark ? 0x000000 : 0xFFFFFF),
      cursorText: null,
      cursorColor: primary,
      bellOverlay: 0xFFFFFF,
    );
  }

  final baseBackground = isDark
      ? Color.alphaBlend(
          cs.surface.withValues(alpha: 0.88),
          const Color(0xFF06080C),
        )
      : Color.alphaBlend(
          cs.surface.withValues(alpha: 0.96),
          const Color(0xFFF7F9FC),
        );
  final foreground = isDark ? const Color(0xFFC8CCD4) : const Color(0xFF1F2937);
  final weak = isDark ? const Color(0xFF59606A) : const Color(0xFF9AA3B2);
  return TerminalTheme(
    background: _packColor(baseBackground),
    foreground: _packColor(foreground),
    selection: _packColor(cs.primary),
    ansi: [
      _packColor(isDark ? const Color(0xFF161A21) : const Color(0xFF4B5563)),
      _packColor(cs.error),
      _packColor(cs.secondary),
      _packColor(Color.lerp(cs.secondary, const Color(0xFFE5B95C), 0.5)!),
      _packColor(cs.primary),
      _packColor(Color.lerp(cs.primary, cs.secondary, 0.45)!),
      _packColor(Color.lerp(cs.secondary, const Color(0xFF58C8D7), 0.55)!),
      _packColor(isDark ? const Color(0xFFD8DCE5) : const Color(0xFF374151)),
      _packColor(weak),
      _packColor(Color.lerp(cs.error, Colors.white, isDark ? 0.18 : 0.1)!),
      _packColor(Color.lerp(cs.secondary, Colors.white, isDark ? 0.16 : 0.08)!),
      _packColor(
        Color.lerp(
          Color.lerp(cs.secondary, const Color(0xFFE5B95C), 0.5)!,
          Colors.white,
          isDark ? 0.2 : 0.1,
        )!,
      ),
      _packColor(Color.lerp(cs.primary, Colors.white, isDark ? 0.16 : 0.08)!),
      _packColor(
        Color.lerp(
          Color.lerp(cs.primary, cs.secondary, 0.45)!,
          Colors.white,
          isDark ? 0.2 : 0.1,
        )!,
      ),
      _packColor(
        Color.lerp(
          Color.lerp(cs.secondary, const Color(0xFF58C8D7), 0.55)!,
          Colors.white,
          isDark ? 0.2 : 0.1,
        )!,
      ),
      _packColor(isDark ? const Color(0xFFF2F4F8) : const Color(0xFF111827)),
    ],
    searchMatch: (bg: 0xFFFF2B, fg: 0x000000),
    searchFocused: (bg: 0x31FF26, fg: 0x000000),
    hintStart: _hyperlinkHintFromScheme(cs),
    cursorText: null,
    cursorColor: _packColor(cs.primary),
    bellOverlay: 0xFFFFFF,
  );
}
