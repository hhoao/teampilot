import '../../models/failed_message_record.dart';

/// Newest [FailedMessageStatus.failed] record, if any.
///
/// Used after launch Retry succeeds so the message that could not be delivered
/// while the PTY was down is re-submitted automatically.
FailedMessageRecord? latestFailedMessageRecord(
  Iterable<FailedMessageRecord> records,
) {
  FailedMessageRecord? latest;
  for (final record in records) {
    if (record.status != FailedMessageStatus.failed) continue;
    if (latest == null || record.createdAt.isAfter(latest.createdAt)) {
      latest = record;
    }
  }
  return latest;
}
