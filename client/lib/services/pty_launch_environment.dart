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
}
