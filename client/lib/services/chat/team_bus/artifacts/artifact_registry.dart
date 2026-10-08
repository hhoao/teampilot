import 'artifact_exceptions.dart';
import 'artifact_handle.dart';

/// In-memory, session-scoped registry of published [ArtifactHandle]s.
///
/// Handles live only as long as the session/mount that owns this registry
/// (cleared on teardown via [clear]); a [ttl] additionally evicts long-unfetched
/// handles so the inbox does not grow unbounded (see §4.2 inbox lifecycle).
///
/// Collision policy: a second publish under an existing name is rejected unless
/// `overwrite: true` is passed (mirrors the fetch destination-conflict default).
class ArtifactRegistry {
  ArtifactRegistry({this.ttl = const Duration(hours: 6)});

  final Duration ttl;
  final Map<String, ArtifactHandle> _byName = <String, ArtifactHandle>{};

  /// Register [handle]. Throws [ArtifactNameCollisionException] when a handle
  /// with the same name already exists and [overwrite] is false.
  void register(ArtifactHandle handle, {bool overwrite = false}) {
    final existing = _byName[handle.name];
    if (existing != null && !overwrite) {
      throw ArtifactNameCollisionException(handle.name);
    }
    _byName[handle.name] = handle;
  }

  /// Currently-registered handles (no implicit eviction; call [evictExpired]
  /// first if you need TTL semantics).
  List<ArtifactHandle> list() => List.unmodifiable(_byName.values);

  ArtifactHandle? byName(String name) => _byName[name];

  /// Drop handles whose age (relative to [nowMs]) exceeds [ttl]. Returns the
  /// number evicted.
  int evictExpired(int nowMs) {
    final cutoff = nowMs - ttl.inMilliseconds;
    final expired = [
      for (final e in _byName.entries)
        if (e.value.publishedAtMs < cutoff) e.key,
    ];
    for (final name in expired) {
      _byName.remove(name);
    }
    return expired.length;
  }

  /// Drop every handle (session/mount teardown).
  void clear() => _byName.clear();
}
