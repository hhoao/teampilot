import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/latest_failed_message.dart';
import 'package:teampilot/models/failed_message_record.dart';

void main() {
  test('returns null when there is no failed or sending record', () {
    expect(latestFailedMessageRecord(const []), isNull);
    expect(
      latestFailedMessageRecord([
        FailedMessageRecord(
          id: 'a',
          text: 'sent',
          createdAt: DateTime.utc(2026, 1, 1),
          status: FailedMessageStatus.sent,
        ),
      ]),
      isNull,
    );
  });

  test('picks the newest failed record by createdAt', () {
    final older = FailedMessageRecord(
      id: 'old',
      text: 'first',
      createdAt: DateTime.utc(2026, 1, 1),
      status: FailedMessageStatus.failed,
    );
    final newer = FailedMessageRecord(
      id: 'new',
      text: 'second',
      createdAt: DateTime.utc(2026, 1, 2),
      status: FailedMessageStatus.failed,
    );
    final sending = FailedMessageRecord(
      id: 's',
      text: 'ignore-when-failed-exists',
      createdAt: DateTime.utc(2026, 1, 3),
      status: FailedMessageStatus.sending,
    );

    expect(
      latestFailedMessageRecord([older, sending, newer])?.id,
      'new',
    );
  });

  test('falls back to newest sending when no failed record exists', () {
    final olderSending = FailedMessageRecord(
      id: 's1',
      text: 'first',
      createdAt: DateTime.utc(2026, 1, 1),
      status: FailedMessageStatus.sending,
    );
    final newerSending = FailedMessageRecord(
      id: 's2',
      text: 'second',
      createdAt: DateTime.utc(2026, 1, 2),
      status: FailedMessageStatus.sending,
    );

    expect(
      latestFailedMessageRecord([olderSending, newerSending])?.id,
      's2',
    );
  });
}
