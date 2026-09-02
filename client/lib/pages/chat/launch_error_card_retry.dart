import '../../cubits/chat/latest_failed_message.dart';
import '../../models/failed_message_record.dart';

/// Chat launch-error card Retry: redeliver latest failed/sending via the
/// bubble path, or reconnect-only when nothing to redeliver.
Future<void> runLaunchErrorCardRetry({
  required Future<List<FailedMessageRecord>> Function() loadRecords,
  required Future<void> Function(FailedMessageRecord record) retryFailed,
  required void Function() reconnectOnly,
}) async {
  final latest = latestFailedMessageRecord(await loadRecords());
  if (latest == null) {
    reconnectOnly();
    return;
  }
  await retryFailed(latest);
}
