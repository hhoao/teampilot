

/// Environment hints for embedded PTY sessions so child CLIs emit OSC 8 links.
abstract final class PtyLaunchEnvironment {
  /// VTE-based terminals (GNOME Terminal, etc.) set this; Claude Code also treats
  /// [vteVersion] ≥ 6800 as hyperlink-capable in some builds.
  static const String termProgram = 'gnome-terminal';

  /// VTE 0.68+ supports OSC 8 hyperlinks (version string is major*100 + minor*10).
  static const String vteVersion = '6800';

  static const Map<String, String> hyperlinkIdentity = {
    'TERM_PROGRAM': termProgram,
    'VTE_VERSION': vteVersion,
  };

  /// Merges [hyperlinkIdentity] into [env] without overriding existing keys.
  static void applyHyperlinkIdentity(Map<String, String> env) {
    for (final entry in hyperlinkIdentity.entries) {
      env.putIfAbsent(entry.key, () => entry.value);
    }
  }

  /// Advertises the embedded terminal's light/dark via `COLORFGBG`
  /// (`foreground;background`, ANSI palette indices). CLIs that detect the
  /// terminal background from the environment at startup — notably Codex, which
  /// ignores our OSC 11 / mode-2031 color-scheme signals — read this to pick a
  /// matching theme. `[background]` is the themed default background packed as
  /// `0xRRGGBB`; we map it to `0` (black, dark) or `15` (bright white, light),
  /// the two ends of the range each detector classifies (bg ≤ 6 ⇒ dark,
  /// bg ≥ 7 ⇒ light).
  ///
  /// Set unconditionally (overriding any inherited value): the host terminal we
  /// were launched from is the wrong context — the child CLI must see *our*
  /// embedded background, not the desktop's.
  static void applyColorScheme(Map<String, String> env, {required int background}) {
    final r = (background >> 16) & 0xFF;
    final g = (background >> 8) & 0xFF;
    final b = background & 0xFF;
    // Rec. 709 relative luminance, midpoint 128 — mirrors the engine's
    // `is_dark_bg` so COLORFGBG and the OSC 997 report can't disagree.
    final isDark = 0.2126 * r + 0.7152 * g + 0.0722 * b < 128.0;
    env['COLORFGBG'] = isDark ? '15;0' : '0;15';
  }
}
