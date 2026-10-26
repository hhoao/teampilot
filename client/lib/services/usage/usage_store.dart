import '../../models/session_usage.dart';

class UsageAppendResult {
  const UsageAppendResult({
    this.inserted = 0,
    this.updated = 0,
    this.skipped = 0,
  });

  final int inserted;
  final int updated;
  final int skipped;
}

/// Persistence seam for usage events. Implementations must be idempotent per
/// [SessionUsageEvent.requestId].
abstract interface class UsageStore {
  Future<UsageAppendResult> upsert(Iterable<SessionUsageEvent> events);

  /// Latest revision per request id, oldest timestamp first.
  Future<List<SessionUsageEvent>> readLatest();
}
