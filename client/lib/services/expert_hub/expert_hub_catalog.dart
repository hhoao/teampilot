import '../../models/discoverable_member.dart';
import 'expert_hub_source.dart';

/// Immutable resolved view of every discoverable expert, keyed by catalog key.
/// Precedence (local clone > registry > builtin) is whatever the backing
/// source's `fetchMembers` merge produces.
class MemberCatalogSnapshot {
  MemberCatalogSnapshot(Map<String, DiscoverableMember> byKey)
    : byKey = Map<String, DiscoverableMember>.unmodifiable(byKey);

  final Map<String, DiscoverableMember> byKey;

  DiscoverableMember? lookup(String? key) => byKey[key?.trim() ?? ''];
}

/// One catalog load per process, shared by every consumer. Single-flight:
/// concurrent callers await the same fetch. [invalidate] clears the snapshot
/// (call after local expert mutations); [refresh] reloads immediately.
class ExpertHubCatalog {
  ExpertHubCatalog({required ExpertHubSource source}) : _source = source;

  final ExpertHubSource _source;
  MemberCatalogSnapshot? _snapshot;
  Future<MemberCatalogSnapshot>? _pending;

  Future<MemberCatalogSnapshot> snapshot() {
    final cached = _snapshot;
    if (cached != null) return Future.value(cached);
    return _pending ??= _load();
  }

  Future<MemberCatalogSnapshot> refresh() {
    invalidate();
    return snapshot();
  }

  void invalidate() {
    _snapshot = null;
    _pending = null;
  }

  Future<MemberCatalogSnapshot> _load() {
    // Capture this load's identity so a concurrent invalidate()/refresh() that
    // swaps _pending mid-flight does not let a stale result win. _load must be
    // sync so the future stored in _pending is the very one compared here.
    late final Future<MemberCatalogSnapshot> pending;
    pending = _source.fetchMembers().then(
      (members) {
        final snap = MemberCatalogSnapshot({for (final m in members) m.key: m});
        if (identical(_pending, pending)) {
          _snapshot = snap;
          _pending = null;
        }
        return snap;
      },
      // A failed load must not poison the catalog: clear _pending so the next
      // snapshot() retries instead of returning this rejected future forever.
      onError: (Object error, StackTrace stack) {
        if (identical(_pending, pending)) _pending = null;
        Error.throwWithStackTrace(error, stack);
      },
    );
    return pending;
  }
}
