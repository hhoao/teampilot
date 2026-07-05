/// Deferred full-screen automation retries (idle-watch backed).
final class PtyAutomationRetryQueue {
  PtyAutomationRetryQueue({
    required this.retryIntervalMs,
    required this.maxAttempts,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int retryIntervalMs;
  final int maxAttempts;
  final int Function() _nowMs;

  final Map<String, _PendingRetry> _pending = {};

  bool isPending(String key) => _pending.containsKey(key);

  /// Schedules or bumps a retry for [key]. Returns false when budget exhausted.
  bool schedule({
    required String key,
    required String sessionId,
    required String memberId,
    required String text,
  }) {
    final prev = _pending[key];
    final attempt = (prev?.attempt ?? 0) + 1;
    if (attempt > maxAttempts) {
      _pending.remove(key);
      return false;
    }
    _pending[key] = _PendingRetry(
      sessionId: sessionId,
      memberId: memberId,
      text: text,
      nextRetryAtMs: _nowMs() + retryIntervalMs,
      attempt: attempt,
    );
    return true;
  }

  void clear(String key) => _pending.remove(key);

  /// Entries ready to run (due and not externally blocked).
  List<PtyAutomationRetryTick> due({required bool Function(String key) blocked}) {
    final now = _nowMs();
    final ready = <PtyAutomationRetryTick>[];
    for (final entry in _pending.entries.toList()) {
      if (entry.value.nextRetryAtMs > now) continue;
      if (blocked(entry.key)) continue;
      final pending = entry.value;
      _pending.remove(entry.key);
      ready.add(
        PtyAutomationRetryTick(
          key: entry.key,
          sessionId: pending.sessionId,
          memberId: pending.memberId,
          text: pending.text,
          attempt: pending.attempt,
        ),
      );
    }
    return ready;
  }
}

final class PtyAutomationRetryTick {
  const PtyAutomationRetryTick({
    required this.key,
    required this.sessionId,
    required this.memberId,
    required this.text,
    required this.attempt,
  });

  final String key;
  final String sessionId;
  final String memberId;
  final String text;
  final int attempt;
}

final class _PendingRetry {
  const _PendingRetry({
    required this.sessionId,
    required this.memberId,
    required this.text,
    required this.nextRetryAtMs,
    required this.attempt,
  });

  final String sessionId;
  final String memberId;
  final String text;
  final int nextRetryAtMs;
  final int attempt;
}
