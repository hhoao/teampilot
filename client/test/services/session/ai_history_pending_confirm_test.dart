import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/failed_message_record.dart';
import 'package:teampilot/services/session/ai_history_pending_confirm.dart';

void main() {
  final record = FailedMessageRecord(
    id: 'pending:1',
    text: 'hello   world',
    createdAt: DateTime.utc(2026, 1, 1, 12),
    status: FailedMessageStatus.sending,
  );

  test('empty messages do not confirm', () {
    expect(
      transcriptConfirmsPendingRecord(record: record, messages: const []),
      isFalse,
    );
  });

  test('normalized text match confirms', () {
    expect(
      transcriptConfirmsPendingRecord(
        record: record,
        messages: [
          const AiMessage(
            id: 'u1',
            role: AiRole.user,
            parts: [AiTextPart(text: 'hello world')],
          ),
        ],
      ),
      isTrue,
    );
  });

  test('prior unmatched history does not confirm', () {
    expect(
      transcriptConfirmsPendingRecord(
        record: record,
        messages: [
          const AiMessage(
            id: 'u0',
            role: AiRole.user,
            parts: [AiTextPart(text: 'older')],
          ),
        ],
      ),
      isFalse,
    );
  });

  test('user createdAt within skew of record confirms', () {
    expect(
      transcriptConfirmsPendingRecord(
        record: record,
        messages: [
          AiMessage(
            id: 'u1',
            role: AiRole.user,
            parts: const [AiTextPart(text: '<command-name>/x</command-name>')],
            createdAt: DateTime.utc(2026, 1, 1, 12, 0, 1),
          ),
        ],
      ),
      isTrue,
    );
  });

  test('user createdAt before record minus skew does not confirm', () {
    expect(
      transcriptConfirmsPendingRecord(
        record: record,
        messages: [
          AiMessage(
            id: 'u0',
            role: AiRole.user,
            parts: const [AiTextPart(text: 'older')],
            createdAt: DateTime.utc(2025, 12, 31),
          ),
        ],
      ),
      isFalse,
    );
  });
}
