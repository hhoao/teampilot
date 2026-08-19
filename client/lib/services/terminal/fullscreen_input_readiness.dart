/// When a full-screen TUI is actually ready for paste+CR inject.
///
/// Boot-frame heuristics only prove "something painted". Codex (and Cursor)
/// can paint splash / trust screens first; inject must wait for composer
/// chrome or a status footer that only exists after those gates.
final class FullscreenInputReadiness {
  const FullscreenInputReadiness({
    this.readyNeedles = const [],
    this.bootGateNeedles = const [],
  });

  /// Probe-window substrings that mean the composer/input surface is up.
  /// Empty: boot frame is enough (Claude Ink, OpenCode, FlashskyAI).
  final List<String> readyNeedles;

  /// First-run / trust copy. Callers may send a CR to dismiss.
  final List<String> bootGateNeedles;

  static const bootFrameOnly = FullscreenInputReadiness();

  bool get waitsForSurface => readyNeedles.isNotEmpty;

  bool isReady(String probeWindow) {
    if (!waitsForSurface) return true;
    return readyNeedles.any(probeWindow.contains);
  }

  bool needsBootGateNudge(String probeWindow) =>
      bootGateNeedles.any(probeWindow.contains);
}

bool isTerminalInputSurfaceReady({
  required FullscreenInputReadiness? readiness,
  required String probeWindow,
}) {
  if (readiness == null) return true;
  return readiness.isReady(probeWindow);
}
