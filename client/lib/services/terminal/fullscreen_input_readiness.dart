/// When a full-screen TUI is actually ready for paste+CR inject.
///
/// Boot-frame heuristics only prove "something painted". Codex (and Cursor)
/// can paint splash / trust screens first; inject must wait for composer
/// chrome or a status footer that only exists after those gates.
///
/// Even after chrome appears, some TUIs (Codex) paint an interactive-looking
/// composer before Enter is bound. [readyDwell] covers that gap — the real
/// Codex PTY deliver test waits 1s after `default ·` before paste+CR.
final class FullscreenInputReadiness {
  const FullscreenInputReadiness({
    this.readyNeedles = const [],
    this.bootGateNeedles = const [],
    this.readyDwell = Duration.zero,
  });

  /// Probe-window substrings that mean the composer/input surface is up.
  /// Empty: boot frame is enough (Claude Ink, OpenCode, FlashskyAI).
  final List<String> readyNeedles;

  /// First-run / trust copy. Callers may send a CR to dismiss.
  final List<String> bootGateNeedles;

  /// How long [readyNeedles] must stay visible before paste+CR.
  /// Zero: ready as soon as needles match (or immediately when unused).
  final Duration readyDwell;

  static const bootFrameOnly = FullscreenInputReadiness();

  bool get waitsForSurface => readyNeedles.isNotEmpty;

  bool isReady(String probeWindow) {
    if (!waitsForSurface) return true;
    return readyNeedles.any(probeWindow.contains);
  }

  bool needsBootGateNudge(String probeWindow) =>
      bootGateNeedles.any(probeWindow.contains);
}

/// Tracks how long a member's composer chrome has been continuously visible.
final class FullscreenInputSurfaceWatch {
  FullscreenInputSurfaceWatch({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  DateTime? _readySince;

  bool observe({
    required FullscreenInputReadiness? readiness,
    required String probeWindow,
  }) {
    if (readiness == null) {
      _readySince = null;
      return true;
    }
    if (!readiness.isReady(probeWindow)) {
      _readySince = null;
      return false;
    }
    if (readiness.readyDwell <= Duration.zero) {
      _readySince = null;
      return true;
    }
    _readySince ??= _now();
    return _now().difference(_readySince!) >= readiness.readyDwell;
  }
}

bool isTerminalInputSurfaceReady({
  required FullscreenInputReadiness? readiness,
  required String probeWindow,
}) {
  if (readiness == null) return true;
  return readiness.isReady(probeWindow);
}
