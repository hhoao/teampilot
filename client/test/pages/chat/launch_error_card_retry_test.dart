import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/failed_message_record.dart';
import 'package:teampilot/pages/chat/launch_error_card_retry.dart';

void main() {
  test('no records → reconnectOnly', () async {
    var reconnect = 0;
    var retries = 0;
    await runLaunchErrorCardRetry(
      loadRecords: () async => const [],
      retryFailed: (_) async {
        retries++;
      },
      reconnectOnly: () => reconnect++,
    );
    expect(reconnect, 1);
    expect(retries, 0);
  });

  test('latest failed → retryFailed with that record', () async {
    FailedMessageRecord? seen;
    await runLaunchErrorCardRetry(
      loadRecords: () async => [
        FailedMessageRecord(
          id: 'pending:old',
          text: 'older',
          createdAt: DateTime.utc(2026, 1, 1),
          status: FailedMessageStatus.failed,
        ),
        FailedMessageRecord(
          id: 'pending:new',
          text: 'newer',
          createdAt: DateTime.utc(2026, 1, 2),
          status: FailedMessageStatus.failed,
        ),
      ],
      retryFailed: (r) async => seen = r,
      reconnectOnly: () {},
    );
    expect(seen?.id, 'pending:new');
  });

  test('sending fallback when no failed → retryFailed', () async {
    FailedMessageRecord? seen;
    await runLaunchErrorCardRetry(
      loadRecords: () async => [
        FailedMessageRecord(
          id: 'pending:send',
          text: 'inflight',
          createdAt: DateTime.utc(2026, 1, 1),
          status: FailedMessageStatus.sending,
        ),
      ],
      retryFailed: (r) async => seen = r,
      reconnectOnly: () {},
    );
    expect(seen?.id, 'pending:send');
  });
}
