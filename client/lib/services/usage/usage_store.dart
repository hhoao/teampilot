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

final class UsageStoreStats {
  const UsageStoreStats({
    required this.lineCount,
    required this.eventCount,
    required this.sizeBytes,
  });

  final int lineCount;
  final int eventCount;
  final int sizeBytes;
}

final class UsageCompactResult {
  const UsageCompactResult({
    required this.beforeLines,
    required this.afterEvents,
    required this.removedLines,
    required this.removedEvents,
  });

  final int beforeLines;
  final int afterEvents;
  final int removedLines;
  final int removedEvents;
}

/// Persistence seam for usage events. Implementations must be idempotent per
/// [SessionUsageEvent.requestId].
abstract interface class UsageStore {
  Future<UsageAppendResult> upsert(Iterable<SessionUsageEvent> events);

  /// Latest revision per request id, oldest timestamp first.
  Future<List<SessionUsageEvent>> readLatest();
}
