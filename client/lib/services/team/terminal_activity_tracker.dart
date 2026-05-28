/// Heuristic workload signal from PTY output (FlashskyAI v1).
///
/// Ignores the initial boot burst: [isWorking] stays false until output has
/// been quiet for [idleAfter], then tracks activity the same way.
class TerminalActivityTracker {
  TerminalActivityTracker({this.idleAfter = const Duration(milliseconds: 2500)});

  final Duration idleAfter;

  bool _armed = false;
  DateTime? _lastActivity;
  DateTime? _bootOutputAt;

  void markActive([DateTime? at]) {
    noteOutput(at);
  }

  void noteOutput([DateTime? at]) {
    final now = at ?? DateTime.now();
    if (_armed) {
      _lastActivity = now;
    } else {
      _bootOutputAt = now;
    }
  }

  void reset() {
    _armed = false;
    _lastActivity = null;
    _bootOutputAt = null;
  }

  /// True when output arrived within [idleAfter] after the boot quiet window.
  bool get isWorking {
    _tryArmAfterBootQuiet();
    if (!_armed) return false;
    final last = _lastActivity;
    if (last == null) return false;
    return DateTime.now().difference(last) < idleAfter;
  }

  void _tryArmAfterBootQuiet() {
    if (_armed) return;
    final bootAt = _bootOutputAt;
    if (bootAt == null) {
      _armed = true;
      return;
    }
    if (DateTime.now().difference(bootAt) >= idleAfter) {
      _armed = true;
      _bootOutputAt = null;
    }
  }
}
