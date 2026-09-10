/// Refcounted per-session flag: an operator send is still in connect/wait/inject.
final class OperatorDeliveryInFlight {
  OperatorDeliveryInFlight({this.onChanged});

  final void Function()? onChanged;
  final Map<String, int> _counts = {};
  final Map<String, int> _generations = {};

  bool isInFlight(String sessionId) {
    final id = sessionId.trim();
    if (id.isEmpty) return false;
    return (_counts[id] ?? 0) > 0;
  }

  Future<T> run<T>(String sessionId, Future<T> Function() action) =>
      runCancellable(sessionId, (_) => action());

  /// Like [run], but hands the action a `cancelled` check that flips true the
  /// moment a compose Stop ([clear]) lands after this run began. Long-running
  /// operator sends (connect + input-ready wait + PTY inject) observe it before
  /// writing to the PTY so a stopped launch never delivers its queued message.
  Future<T> runCancellable<T>(
    String sessionId,
    Future<T> Function(bool Function() cancelled) action,
  ) async {
    final id = sessionId.trim();
    if (id.isEmpty) return action(() => false);
    final generation = _begin(id);
    final cancelled = () => (_generations[id] ?? 0) != generation;
    try {
      return await action(cancelled);
    } finally {
      _end(id, generation);
    }
  }

  /// Zero the count (compose Stop). Later [run] `finally` must not go negative
  /// and must not decrement a newer send's count.
  void clear(String sessionId) {
    final id = sessionId.trim();
    if (id.isEmpty) return;
    if (!_counts.containsKey(id)) return;
    _counts.remove(id);
    _generations[id] = (_generations[id] ?? 0) + 1;
    onChanged?.call();
  }

  int _begin(String id) {
    final generation = _generations[id] ?? 0;
    _counts[id] = (_counts[id] ?? 0) + 1;
    onChanged?.call();
    return generation;
  }

  void _end(String id, int generation) {
    if ((_generations[id] ?? 0) != generation) return;
    final next = (_counts[id] ?? 0) - 1;
    if (next <= 0) {
      if (!_counts.containsKey(id)) return;
      _counts.remove(id);
      onChanged?.call();
      return;
    }
    _counts[id] = next;
  }
}
