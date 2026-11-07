/// One immutable snapshot owned by a single plane object.
///
/// This type exists so plane caches are instance state by construction: the
/// snapshot dies with its owner, and two owners can never observe each other's
/// entries regardless of path strings. Never hold one of these in a `static`
/// field.
final class PlaneSnapshotCache<T> {
  List<T>? _snapshot;

  /// The current frozen snapshot, or `null` when nothing has been loaded.
  List<T>? get snapshot => _snapshot;

  /// Replaces the snapshot with an unmodifiable copy of [values].
  List<T> write(Iterable<T> values) {
    final frozen = List<T>.unmodifiable(values);
    _snapshot = frozen;
    return frozen;
  }

  /// Drops the snapshot so the next read reloads from the plane.
  void invalidate() {
    _snapshot = null;
  }
}
