import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/latest_failed_message.dart';
import 'package:teampilot/models/failed_message_record.dart';

void main() {
  test('returns null when there is no failed record', () {
    expect(latestFailedMessageRecord(const []), isNull);
    expect(
      latestFailedMessageRecord([
        FailedMessageRecord(
          id: 'a',
          text: 'sending',
          createdAt: DateTime.utc(2026, 1, 1),
          status: FailedMessageStatus.sending,
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
      text: 'ignore',
      createdAt: DateTime.utc(2026, 1, 3),
      status: FailedMessageStatus.sending,
    );

    expect(
      latestFailedMessageRecord([older, sending, newer])?.id,
      'new',
    );
  });
}
