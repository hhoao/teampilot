import '../cli/registry/capabilities/session_usage_capability.dart';

/// Persistence seam for per-source scan progress.
abstract interface class UsageCursorStore {
  Future<UsageCursor?> read(String sourceId);

  Future<void> save(String sourceId, UsageCursor cursor);

  Future<void> remove(String sourceId);

  /// Removes cursors whose source no longer exists. Returns the number removed.
  Future<int> prune(Set<String> activeSourceIds);
}
