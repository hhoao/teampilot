import '../../models/failed_message_record.dart';

/// Chat launch-error card Retry: redeliver latest failed/sending via the
/// bubble path, or reconnect-only when nothing to redeliver.
Future<void> runLaunchErrorCardRetry({
  required Future<List<FailedMessageRecord>> Function() loadRecords,
  required Future<bool> Function(FailedMessageRecord record) retryFailed,
  required void Function() reconnectOnly,
}) async {
  final latest = latestFailedMessageRecord(await loadRecords());
  if (latest == null) {
    reconnectOnly();
    return;
  }
  final handled = await retryFailed(latest);
  if (!handled) reconnectOnly();
}

/// Newest undelivered outgoing record for launch-Retry redelivery.
///
/// Prefers [FailedMessageStatus.failed]. Falls back to [FailedMessageStatus.sending]
/// when a send was interrupted mid-flight (PTY died before mark-failed ran).
FailedMessageRecord? latestFailedMessageRecord(
  Iterable<FailedMessageRecord> records,
) {
  FailedMessageRecord? latestFailed;
  FailedMessageRecord? latestSending;
  for (final record in records) {
    switch (record.status) {
      case FailedMessageStatus.failed:
        if (latestFailed == null ||
            record.createdAt.isAfter(latestFailed.createdAt)) {
          latestFailed = record;
        }
      case FailedMessageStatus.sending:
        if (latestSending == null ||
            record.createdAt.isAfter(latestSending.createdAt)) {
          latestSending = record;
        }
      case FailedMessageStatus.sent:
        break;
    }
  }
  return latestFailed ?? latestSending;
}
