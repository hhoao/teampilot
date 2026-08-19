import 'dart:async';

/// Serializes mutations that target the same persisted storage path.
class ManagedProviderStorageLock {
  ManagedProviderStorageLock._();

  static final Map<String, Future<void>> _tails = {};

  static Future<T> run<T>(String path, Future<T> Function() mutation) async {
    final previous = _tails[path];
    final gate = Completer<void>();
    _tails[path] = gate.future;
    try {
      if (previous != null) await previous;
      return await mutation();
    } finally {
      if (identical(_tails[path], gate.future)) _tails.remove(path);
      if (!gate.isCompleted) gate.complete();
    }
  }
}
