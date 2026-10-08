/// Launch-owned cancel token per session.
///
/// Connect jobs stamp [current] and abort when a later [bump] (open, reconnect)
/// makes [matches] false. Lives here so ChatTab is not the source of truth.
final class LaunchGenerationStore {
  final Map<String, int> _generations = <String, int>{};

  int current(String sessionId) => _generations[sessionId] ?? 0;

  int bump(String sessionId) {
    final next = current(sessionId) + 1;
    _generations[sessionId] = next;
    return next;
  }

  bool matches(String sessionId, int generation) =>
      current(sessionId) == generation;

  void drop(String sessionId) => _generations.remove(sessionId);
}
