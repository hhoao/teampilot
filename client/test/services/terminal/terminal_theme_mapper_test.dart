import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_theme_mapper.dart';
import 'package:teampilot/theme/workspace_surface_layers.dart';

void main() {
  test('terminalColorsFromTheme maps palette fields', () {
    const theme = TerminalTheme(
      background: 0x0A0C10,
      foreground: 0xC8CCD4,
      selection: 0x9AA0A8,
      ansi: [
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
      hintStart: (bg: 0x31FF26, fg: 0x000000),
      cursorText: null,
      cursorColor: 0x9AA0A8,
      bellOverlay: 0xFFFFFF,
    );
    final colors = terminalColorsFromTheme(theme);
    expect(colors.background, 0x0A0C10);
    expect(colors.foreground, 0xC8CCD4);
    expect(colors.ansi[1], 0xD04A62);
    expect(colors.searchMatchBg, 0xFFFF2B);
    expect(colors.cursorBody, 0x9AA0A8);
  });

  test('teampilotTerminalTheme classicDark differs from engine defaults', () {
    const defaults = TerminalTheme.defaults;
    final classic = teampilotTerminalTheme(
      const ColorScheme.dark(),
      isDark: true,
      mode: 'classicDark',
    );
    expect(classic.background, isNot(defaults.background));
    expect(classic.ansi[1], isNot(defaults.ansi[1]));
  });

  test('teampilotTerminalTheme hyperlink hint uses ColorScheme primary', () {
    const cs = ColorScheme.dark(primary: Color(0xFF336699));
    final theme = teampilotTerminalTheme(cs, isDark: true, mode: 'adaptive');
    expect(theme.hintStart.bg, 0x336699);
    expect(theme.hintStart.fg, cs.onPrimary.toARGB32() & 0xFFFFFF);
  });

  test('teampilotTerminalTheme adaptive background follows page chrome', () {
    const cs = ColorScheme.light(
      surface: Color(0xFFFFFFFF),
      surfaceContainer: Color(0xFFE8EAED),
    );
    final home = teampilotTerminalTheme(
      cs,
      isDark: false,
      mode: 'adaptive',
      chrome: WorkspacePageChrome.home,
    );
    final workspace = teampilotTerminalTheme(
      cs,
      isDark: false,
      mode: 'adaptive',
      chrome: WorkspacePageChrome.workspace,
    );
    expect(home.background, isNot(workspace.background));
  });
}
