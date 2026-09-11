import 'package:flutter/foundation.dart';

/// Debug-only switch that mutes terminal *rendering* during performance
/// captures, so non-terminal UI work (chat rebuilds, file loading) is not
/// buried under terminal repaint noise in DevTools traces.
///
/// Compile in with `--dart-define=PERF_MUTE_TERMINALS=true`. Terminals keep
/// running: PTY output is still consumed, parsed, and mirrored into the
/// engine grid (screen probes and observation modules keep working) — only
/// the `TerminalView` mount is replaced by a static placeholder, so the grid
/// has no repaint listeners and terminal output no longer schedules frames.
///
/// Pair with `PERF_DRIVER=true` and `tool/dump_live_perf.dart` (see
/// docs/PERFORMANCE_ANALYSIS.md) so the recorded trace stays small enough to
/// export and analyze. Compare against a run without the define to attribute
/// the difference to terminal rendering itself.
class TerminalRenderMute {
  TerminalRenderMute._();

  static const _defineEnabled = bool.fromEnvironment(
    'PERF_MUTE_TERMINALS',
    defaultValue: false,
  );

  /// Test-only override of the compile-time define.
  @visibleForTesting
  static bool? debugOverride;

  /// Whether terminal rendering is muted in this build.
  static bool get enabled => debugOverride ?? _defineEnabled;
}
