import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/conversation_timeline/timeline_merge.dart';
import 'package:teampilot/services/conversation_timeline/timeline_models.dart';

void main() {
  group('incremental merge preserves unchanged message instances', () {
    TimelineEvent cliEvent({
      required String id,
      required String text,
      DateTime? createdAt,
      required int cliOrder,
      AiRole role = AiRole.user,
    }) {
      return TimelineEvent(
        id: id,
        role: role,
        parts: [AiTextPart(text: text)],
        createdAt: createdAt,
        source: 'cli',
        cliOrder: cliOrder,
      );
    }

    TimelineEvent mailboxEvent({
      required String id,
      required String text,
      required DateTime createdAt,
    }) {
      return TimelineEvent(
        id: 'mailbox:$id',
        role: AiRole.user,
        parts: [AiTextPart(text: text)],
        createdAt: createdAt,
        source: 'mailbox',
        deliveryChannel: 'mailbox',
      );
    }

    test('append-only CLI keeps prior AiMessage instances', () {
      final t1 = DateTime.utc(2026, 1, 1, 10);
      final t2 = DateTime.utc(2026, 1, 1, 11);

      final initialEvents = [
        cliEvent(id: 'cli-1', text: 'first', createdAt: t1, cliOrder: 0),
        cliEvent(
          id: 'cli-2',
          text: 'second',
          createdAt: t2,
          cliOrder: 1,
          role: AiRole.assistant,
        ),
      ];
      final initial = mergeTimeline(events: initialEvents, unread: const []);
      final previous = SeatTimelineSnapshot(
        cliMessages: initial.messages,
        mailboxRecords: const [],
        snapshot: initial,
      );

      final cliDelta = CliTimelineAppended(
        events: [
          cliEvent(
            id: 'cli-3',
            text: 'third',
            createdAt: DateTime.utc(2026, 1, 1, 12),
            cliOrder: 2,
            role: AiRole.assistant,
          ),
        ],
      );
      final nextCli = [
        ...initial.messages,
        AiMessage(
          id: 'cli-3',
          role: AiRole.assistant,
          parts: [AiTextPart(text: 'third')],
          createdAt: DateTime.utc(2026, 1, 1, 12),
        ),
      ];
      final allEvents = [
        ...initialEvents,
        cliDelta.events.single,
      ];

      final merged = mergeTimelineIncremental(
        previous: previous,
        cliDelta: cliDelta,
        mailboxDelta: const MailboxTimelineUnchanged(),
        allEvents: allEvents,
        unread: const [],
        nextCliMessages: nextCli,
      );

      expect(merged.messages, hasLength(3));
      expect(identical(merged.messages[0], initial.messages[0]), isTrue);
      expect(identical(merged.messages[1], initial.messages[1]), isTrue);
      expect(identical(merged.messages[2], initial.messages[0]), isFalse);
      expect(identical(merged.messages[2], initial.messages[1]), isFalse);
      expect(
        mergeTimeline(events: allEvents, unread: const []).messages.map((m) => m.id),
        merged.messages.map((m) => m.id),
      );
    });

    test('append-only mailbox reuses unchanged instances outside insert segment', () {
      final t1 = DateTime.utc(2026, 1, 1, 10);
      final t2 = DateTime.utc(2026, 1, 1, 11);
      final t3 = DateTime.utc(2026, 1, 1, 12);

      final initialEvents = [
        cliEvent(id: 'cli-1', text: 'cli user', createdAt: t1, cliOrder: 0),
        cliEvent(
          id: 'cli-2',
          text: 'cli assistant',
          createdAt: t3,
          cliOrder: 1,
          role: AiRole.assistant,
        ),
      ];
      final initial = mergeTimeline(events: initialEvents, unread: const []);
      final previous = SeatTimelineSnapshot(
        cliMessages: initial.messages,
        mailboxRecords: const [],
        snapshot: initial,
      );

      final mailbox = mailboxEvent(
        id: 'mail-1',
        text: 'mailbox user',
        createdAt: t2,
      );
      final allEvents = [...initialEvents, mailbox];
      final mailboxDelta = MailboxTimelineAppended(
        events: [mailbox],
        unread: const [],
      );

      final merged = mergeTimelineIncremental(
        previous: previous,
        cliDelta: const CliTimelineUnchanged(),
        mailboxDelta: mailboxDelta,
        allEvents: allEvents,
        unread: const [],
        nextCliMessages: previous.cliMessages,
      );

      expect(merged.messages.map((m) => m.id), [
        'cli-1',
        'mailbox:mail-1',
        'cli-2',
      ]);
      expect(identical(merged.messages[0], initial.messages[0]), isTrue);
      expect(identical(merged.messages[2], initial.messages[1]), isTrue);
      expect(identical(merged.messages[1], initial.messages[0]), isFalse);
      expect(
        mergeTimeline(events: allEvents, unread: const []).messages.map((m) => m.id),
        merged.messages.map((m) => m.id),
      );
    });

    test('CLI rewrite falls back to full merge with fresh instances', () {
      final t1 = DateTime.utc(2026, 1, 1, 10);
      final initialEvents = [
        cliEvent(id: 'cli-1', text: 'first', createdAt: t1, cliOrder: 0),
        cliEvent(id: 'cli-2', text: 'second', createdAt: t1, cliOrder: 1),
      ];
      final initial = mergeTimeline(events: initialEvents, unread: const []);
      final previous = SeatTimelineSnapshot(
        cliMessages: initial.messages,
        mailboxRecords: const [],
        snapshot: initial,
      );

      final rewrittenEvents = [
        cliEvent(id: 'cli-2', text: 'second', createdAt: t1, cliOrder: 0),
        cliEvent(id: 'cli-1', text: 'first', createdAt: t1, cliOrder: 1),
      ];

      final merged = mergeTimelineIncremental(
        previous: previous,
        cliDelta: const CliTimelineInvalidated(),
        mailboxDelta: const MailboxTimelineUnchanged(),
        allEvents: rewrittenEvents,
        unread: const [],
        nextCliMessages: [
          AiMessage(
            id: 'cli-2',
            role: AiRole.user,
            parts: [AiTextPart(text: 'second')],
            createdAt: t1,
          ),
          AiMessage(
            id: 'cli-1',
            role: AiRole.user,
            parts: [AiTextPart(text: 'first')],
            createdAt: t1,
          ),
        ],
      );

      expect(merged.messages.map((m) => m.id), ['cli-2', 'cli-1']);
      expect(identical(merged.messages[0], initial.messages[0]), isFalse);
      expect(identical(merged.messages[1], initial.messages[1]), isFalse);
    });
  });

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
