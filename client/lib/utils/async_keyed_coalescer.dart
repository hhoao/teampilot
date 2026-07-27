/// Coalesces concurrent async work by [key]: waiters share one [Future].
class AsyncKeyedCoalescer {
  final _inflight = <String, Future<dynamic>>{};

  Future<T> run<T>(String key, Future<T> Function() work) {
    final existing = _inflight[key];
    if (existing != null) return existing as Future<T>;

    final future = work();
    _inflight[key] = future;
    future.then(
      (_) {
        if (identical(_inflight[key], future)) {
          _inflight.remove(key);
        }
      },
      onError: (_) {
        if (identical(_inflight[key], future)) {
          _inflight.remove(key);
        }
      },
    );
    return future;
  }
}
