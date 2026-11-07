import 'home_runtime_identity.dart';

/// One immutable snapshot owned by a single plane object.
///
/// This type exists so plane caches are instance state by construction: the
/// snapshot dies with its owner, and two owners can never observe each other's
/// entries regardless of path strings. Never hold one of these in a `static`
/// field.
///
/// When constructed with a [plane] getter the cache is also *plane-bound*: a
/// snapshot only survives while the plane it was loaded from is still the
/// current plane. Home switches between two hosts that resolve the same
/// `appDataRoot` therefore cannot be served from each other's snapshots.
final class PlaneSnapshotCache<T> {
  PlaneSnapshotCache({HomeRuntimeIdentity Function()? plane}) : _plane = plane;

  /// Reads the plane the owning runtime is bound to right now, or `null` for
  /// an unbound cache (no invalidation on swap).
  final HomeRuntimeIdentity Function()? _plane;

  List<T>? _snapshot;
  HomeRuntimeIdentity? _boundPlane;

  /// The current frozen snapshot, or `null` when nothing has been loaded or
  /// the snapshot belongs to a plane that is no longer current.
  List<T>? get snapshot {
    if (_snapshot != null) {
      final bound = _boundPlane;
      final current = _plane?.call();
      if (bound != null && current != null && current != bound) {
        _snapshot = null;
        _boundPlane = null;
      }
    }
    return _snapshot;
  }

  /// Replaces the snapshot with an unmodifiable copy of [values].
  ///
  /// The snapshot is bound to [forPlane] when given, otherwise to the plane
  /// currently reported by the [plane] getter. A [forPlane] that is no longer
  /// current means the load raced a home swap: its result is returned to the
  /// caller but not installed, so the retired plane's data can never be read
  /// through the new plane.
  List<T> write(Iterable<T> values, {HomeRuntimeIdentity? forPlane}) {
    final frozen = List<T>.unmodifiable(values);
    final current = _plane?.call();
    if (forPlane != null && current != null && current != forPlane) {
      return frozen;
    }
    _snapshot = frozen;
    _boundPlane = forPlane ?? current;
    return frozen;
  }

  /// Drops the snapshot and its plane binding so the next read reloads from
  /// the current plane.
  void invalidate() {
    _snapshot = null;
    _boundPlane = null;
  }
}
