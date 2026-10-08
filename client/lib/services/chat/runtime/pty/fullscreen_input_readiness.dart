/// When a full-screen TUI is actually ready for paste+CR inject.
///
/// Boot-frame heuristics only prove "something painted". Codex (and Cursor)
/// can paint splash / trust screens first; inject must wait for composer
/// chrome or a status footer that only exists after those gates.
///
/// Even after chrome appears, some TUIs (Codex, Cursor) paint an
/// interactive-looking composer before Enter is bound. Codex `--resume`
/// streams history after chrome; Cursor redraws the whole screen at
/// startup. [readyDwell] is the quiet window after needles match **and**
/// the probe contents stop changing.
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

  /// How long [readyNeedles] must stay visible on an **unchanged** probe
  /// window before paste+CR. History replay, MOTD, or layout shifts reset
  /// the timer. Zero: ready as soon as needles match (or immediately when unused).
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

/// Tracks how long a member's composer chrome has been continuously visible
/// on a stable probe window.
final class FullscreenInputSurfaceWatch {
  FullscreenInputSurfaceWatch({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  DateTime? _readySince;
  String? _stableWindow;

  bool observe({
    required FullscreenInputReadiness? readiness,
    required String probeWindow,
  }) {
    if (readiness == null) {
      _reset();
      return true;
    }
    if (!readiness.isReady(probeWindow)) {
      _reset();
      return false;
    }
    if (readiness.readyDwell <= Duration.zero) {
      _reset();
      return true;
    }
    if (_stableWindow != probeWindow) {
      _stableWindow = probeWindow;
      _readySince = _now();
      return false;
    }
    return _now().difference(_readySince!) >= readiness.readyDwell;
  }

  void _reset() {
    _readySince = null;
    _stableWindow = null;
  }
}

bool isTerminalInputSurfaceReady({
  required FullscreenInputReadiness? readiness,
  required String probeWindow,
}) {
  if (readiness == null) return true;
  return readiness.isReady(probeWindow);
}
