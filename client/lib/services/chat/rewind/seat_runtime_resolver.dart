import '../../../models/runtime_target.dart';
import '../../storage/runtime_context.dart';

final class SeatRuntimeResolver {
  SeatRuntimeResolver({
    required Future<RuntimeContext> Function(RuntimeTarget target) resolve,
  }) : _resolve = resolve;

  final Future<RuntimeContext> Function(RuntimeTarget target) _resolve;
  final _cache = <String, Future<RuntimeContext>>{};

  final _values = <String, RuntimeContext>{};

  Future<RuntimeContext> forTarget(RuntimeTarget target) {
    final existing = _cache[target.id];
    if (existing != null) return existing;
    final future = _resolve(target).then((ctx) {
      _values[target.id] = ctx;
      return ctx;
    });
    _cache[target.id] = future;
    return future;
  }

  RuntimeContext? peek(String targetId) => _values[targetId];

  void invalidate(String targetId) {
    _cache.remove(targetId);
    _values.remove(targetId);
  }

  void clear() {
    _cache.clear();
    _values.clear();
  }
}
