import '../../git/git_command_runner.dart';
import '../../storage/runtime_context.dart';

final class RewindCapability {
  const RewindCapability({
    required this.available,
    this.version,
    this.pathspecFromFile = false,
  });
  final bool available;
  final String? version;
  final bool pathspecFromFile;
  static const unavailable = RewindCapability(available: false);
}

final class RewindCapabilityCache {
  RewindCapabilityCache({
    required GitCommandRunner Function(RuntimeContext) runnerFor,
  }) : _runnerFor = runnerFor;

  final GitCommandRunner Function(RuntimeContext) _runnerFor;
  final _cache = <String, Future<RewindCapability>>{};
  final _values = <String, RewindCapability>{};

  Future<RewindCapability> forContext(RuntimeContext ctx) {
    final existing = _cache[ctx.target.id];
    if (existing != null) return existing;
    final future = _probe(ctx).then((cap) {
      _values[ctx.target.id] = cap;
      return cap;
    });
    _cache[ctx.target.id] = future;
    return future;
  }

  RewindCapability? peek(String targetId) => _values[targetId];

  Future<RewindCapability> _probe(RuntimeContext ctx) async {
    final cap = await _runnerFor(ctx).probe();
    return RewindCapability(
      available: cap.available,
      version: cap.version,
      pathspecFromFile: cap.pathspecFromFile,
    );
  }

  void invalidate(String targetId) {
    _cache.remove(targetId);
    _values.remove(targetId);
  }

  void clear() {
    _cache.clear();
    _values.clear();
  }
}
