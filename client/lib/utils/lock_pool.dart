import 'package:synchronized/synchronized.dart';

/// Returns one shared [Lock] per [key] so concurrent async work serializes per key.
class LockPool {
  final _locks = <String, Lock>{};

  Future<T> synchronized<T>(String key, Future<T> Function() fn) {
    return _locks.putIfAbsent(key, Lock.new).synchronized(fn);
  }
}
