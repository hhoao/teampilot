/// Wraps [load] so a successful result is memoized while a failure is not.
///
/// Callers share the in-flight future. After success, every later call returns
/// the same completed future. On error the memo is cleared (only when it still
/// refers to that attempt) so the next call retries — required for boot loads
/// that run again on reconnect.
Future<T> Function() retryableMemo<T>(Future<T> Function() load) {
  Future<T>? memo;
  return () {
    final existing = memo;
    if (existing != null) return existing;
    late final Future<T> future;
    future = load().then<T>(
      (value) => value,
      onError: (Object error, StackTrace stackTrace) {
        if (identical(memo, future)) memo = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    memo = future;
    return future;
  };
}
