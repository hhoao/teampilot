import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/conversation_timeline/timeline_merge.dart';
import 'package:teampilot/services/conversation_timeline/timeline_models.dart';

void main() {
  group('mergeTimeline', () {
    test('interleaves CLI and mailbox user messages by createdAt', () {
      final t1 = DateTime.utc(2026, 1, 1, 10);
      final t2 = DateTime.utc(2026, 1, 1, 11);
      final t3 = DateTime.utc(2026, 1, 1, 12);

      final snapshot = mergeTimeline(
        events: [
          TimelineEvent(
            id: 'cli-user-1',
            role: AiRole.user,
            parts: [AiTextPart(text: 'cli user')],
            createdAt: t1,
            source: 'cli',
            cliOrder: 0,
          ),
          TimelineEvent(
            id: 'cli-assistant-1',
            role: AiRole.assistant,
            parts: [AiTextPart(text: 'cli assistant')],
            createdAt: t3,
            source: 'cli',
            cliOrder: 1,
          ),
          TimelineEvent(
            id: 'mailbox:mail-1',
            role: AiRole.user,
            parts: [AiTextPart(text: 'mailbox user')],
            createdAt: t2,
            source: 'mailbox',
            deliveryChannel: 'mailbox',
          ),
        ],
        unread: const [],
      );

      expect(snapshot.messages.map((m) => m.id), [
        'cli-user-1',
        'mailbox:mail-1',
        'cli-assistant-1',
      ]);
      expect(snapshot.messages[1].deliveryChannel, 'mailbox');
      expect(snapshot.messages[0].deliveryChannel, isNull);
    });

    test('passes unread through without adding them to messages', () {
      const unread = [
        UnreadUserMail(id: 'mail-unread-1', content: 'queued text'),
        UnreadUserMail(id: 'mail-unread-2', content: 'parked text'),
      ];

      final snapshot = mergeTimeline(
        events: [
          TimelineEvent(
            id: 'cli-assistant-1',
            role: AiRole.assistant,
            parts: [AiTextPart(text: 'reply')],
            createdAt: DateTime.utc(2026, 1, 1, 10),
            source: 'cli',
          ),
        ],
        unread: unread,
      );

      expect(snapshot.unreadUserMails, unread);
      expect(snapshot.messages, hasLength(1));
      expect(
        snapshot.messages.map((m) => m.id),
        isNot(contains('mail-unread-1')),
      );
      expect(
        snapshot.messages.map((m) => m.id),
        isNot(contains('mail-unread-2')),
      );
    });

    test('dedupes same id with last write winning', () {
      final t1 = DateTime.utc(2026, 1, 1, 10);
      final t2 = DateTime.utc(2026, 1, 1, 11);

      final snapshot = mergeTimeline(
        events: [
          TimelineEvent(
            id: 'dup-id',
            role: AiRole.user,
            parts: [AiTextPart(text: 'first')],
            createdAt: t1,
            source: 'mailbox',
            deliveryChannel: 'mailbox',
          ),
          TimelineEvent(
            id: 'dup-id',
            role: AiRole.user,
            parts: [AiTextPart(text: 'second')],
            createdAt: t2,
            source: 'mailbox',
            deliveryChannel: 'mailbox',
          ),
        ],
        unread: const [],
      );

      expect(snapshot.messages, hasLength(1));
      expect(snapshot.messages.single.id, 'dup-id');
      expect(
        (snapshot.messages.single.parts.single as AiTextPart).text,
        'second',
      );
    });

    test('preserves relative CLI order when createdAt is missing', () {
      final snapshot = mergeTimeline(
        events: [
          TimelineEvent(
            id: 'cli-b',
            role: AiRole.user,
            parts: [AiTextPart(text: 'b')],
            source: 'cli',
            cliOrder: 1,
          ),
          TimelineEvent(
            id: 'cli-a',
            role: AiRole.user,
            parts: [AiTextPart(text: 'a')],
            source: 'cli',
            cliOrder: 0,
          ),
          TimelineEvent(
            id: 'mailbox:mail-1',
            role: AiRole.user,
            parts: [AiTextPart(text: 'mailbox')],
            createdAt: DateTime.utc(2026, 1, 1, 10),
            source: 'mailbox',
            deliveryChannel: 'mailbox',
          ),
        ],
        unread: const [],
      );

      expect(snapshot.messages.map((m) => m.id), [
        'cli-a',
        'cli-b',
        'mailbox:mail-1',
      ]);
    });
  });
}
