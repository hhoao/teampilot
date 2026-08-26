import 'dart:io';

import '../host/host_shell_path_resolver.dart';

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
  static void applyColorScheme(
    Map<String, String> env, {
    required int background,
  }) {
    final r = (background >> 16) & 0xFF;
    final g = (background >> 8) & 0xFF;
    final b = background & 0xFF;
    // Rec. 709 relative luminance, midpoint 128 — mirrors the engine's
    // `is_dark_bg` so COLORFGBG and the OSC 997 report can't disagree.
    final isDark = 0.2126 * r + 0.7152 * g + 0.0722 * b < 128.0;
    env['COLORFGBG'] = isDark ? '15;0' : '0;15';
  }

  /// Merges the user's login-shell PATH into a local PTY child environment.
  ///
  /// Semantics (spec 2026-08-26): when a login-shell PATH is cached, deliberate
  /// app prepends survive first, then cached login-shell dirs fill in, then
  /// remaining host-base dirs. When no resolution is cached yet, the inherited
  /// PATH order is kept intact and existing-but-missing fallback candidate dirs
  /// are appended instead — cheap existsSync checks that rescue Homebrew-style
  /// installs even if warmup lost the race with an instant reconnect.
  static void applyLocalLoginShellPath(
    Map<String, String> env, {
    required String? hostBasePath,
    required bool posixDesktop,
    List<String>? candidateDirs,
  }) {
    if (!posixDesktop) return;
    final currentEntries = (env['PATH'] ?? '')
        .split(':')
        .where((entry) => entry.isNotEmpty)
        .toList();
    final hostBaseEntries = (hostBasePath ?? '')
        .split(':')
        .where((entry) => entry.isNotEmpty)
        .toList();

    final result = <String>[];
    final resolved = HostShellPathResolver.cachedPath;
    if (resolved != null) {
      result.addAll(
        currentEntries.where((entry) => !hostBaseEntries.contains(entry)),
      );
      for (final entry in resolved.split(':')) {
        if (entry.isNotEmpty && !result.contains(entry)) result.add(entry);
      }
    } else {
      result.addAll(currentEntries);
      for (final dir
          in candidateDirs ?? HostShellPathResolver.fallbackCandidateDirs()) {
        if (!Directory(dir).existsSync()) continue;
        if (result.contains(dir)) continue;
        result.add(dir);
      }
    }

    for (final entry in hostBaseEntries) {
      if (entry.isEmpty || result.contains(entry)) continue;
      result.add(entry);
    }

    if (result.isNotEmpty) env['PATH'] = result.join(':');
  }

  /// Full process environment for [Pty.start], including OSC 8 identity hints.
  ///
  /// [inheritHostEnvironment] is true for local/WSL PTY (PATH, locale, …).
  /// SSH remote launches must pass false so the control-plane host's proxy and
  /// API endpoint env vars are not exported onto the work machine.
  static Map<String, String> buildPtyEnvironment(
    Map<String, String>? environment, {
    int? themeBackground,
    bool inheritHostEnvironment = true,
  }) {
    final merged = <String, String>{
      if (inheritHostEnvironment) ...Platform.environment,
      if (environment != null) ...environment,
    };
    applyHyperlinkIdentity(merged);
    if (themeBackground != null) {
      applyColorScheme(merged, background: themeBackground);
    }
    if (Platform.isWindows) {
      final path = merged['Path'] ?? merged['PATH'];
      if (path != null && path.isNotEmpty) {
        merged['PATH'] = path;
      }
    }
    if (inheritHostEnvironment && (Platform.isMacOS || Platform.isLinux)) {
      applyLocalLoginShellPath(
        merged,
        hostBasePath: Platform.environment['PATH'],
        posixDesktop: true,
      );
    }
    return merged;
  }
}
