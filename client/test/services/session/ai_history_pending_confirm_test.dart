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
            parts: const [AiTextPart(text: 'hello world <rewritten>')],
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

  test('unrelated later send does not confirm a failed record', () {
    // A failed at 12:00; an unrelated message B landed at 12:05. B's timestamp
    // alone must not delete A's failed record (data-loss regression).
    expect(
      transcriptConfirmsPendingRecord(
        record: record,
        messages: [
          AiMessage(
            id: 'u0',
            role: AiRole.user,
            parts: const [AiTextPart(text: 'older turn')],
            createdAt: DateTime.utc(2026, 1, 1, 11, 58),
          ),
          const AiMessage(
            id: 'u1',
            role: AiRole.assistant,
            parts: [AiTextPart(text: 'assistant reply')],
          ),
          AiMessage(
            id: 'u2',
            role: AiRole.user,
            parts: const [AiTextPart(text: 'different message')],
            createdAt: DateTime.utc(2026, 1, 1, 12, 5),
          ),
        ],
      ),
      isFalse,
    );
  });

  test('rewritten tip at/after record time still confirms (timestamp arm)', () {
    // The record's send landed but the CLI rewrote the text to a slash form
    // with no normalized-text overlap beyond the window: the tip user message
    // is at/after the record timestamp and no different-text turn follows, so
    // the recency signal holds.
    expect(
      transcriptConfirmsPendingRecord(
        record: record,
        messages: [
          AiMessage(
            id: 'u0',
            role: AiRole.user,
            parts: const [AiTextPart(text: 'older turn')],
            createdAt: DateTime.utc(2026, 1, 1, 11, 58),
          ),
          AiMessage(
            id: 'u1',
            role: AiRole.user,
            parts: const [
              AiTextPart(text: 'hello world <rewritten-by-cli>'),
            ],
            createdAt: DateTime.utc(2026, 1, 1, 12, 0, 1),
          ),
        ],
      ),
      isTrue,
    );
  });
}
