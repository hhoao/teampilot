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

  Future<T> run<T>(String sessionId, Future<T> Function() action) async {
    final id = sessionId.trim();
    if (id.isEmpty) return action();
    final generation = _begin(id);
    try {
      return await action();
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
