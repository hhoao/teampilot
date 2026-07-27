import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/conversation_timeline/mailbox_user_source.dart';
import 'package:teampilot/services/conversation_timeline/timeline_models.dart';
import 'package:teampilot/services/team_bus/persistence/bus_message_log.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

LoggedMessage _record({
  required String id,
  required String from,
  required String content,
  required int createdAt,
  bool read = false,
  int seq = 0,
}) {
  return LoggedMessage(
    seq: seq,
    message: TeamMessage(id: id, from: from, to: 'leader', content: content),
    createdAt: createdAt,
    read: read,
  );
}

void main() {
  group('partitionMailboxUserRecords', () {
    test('ignores teammate mail and partitions read vs unread user mail', () {
      final records = [
        _record(
          id: 'read-1',
          from: TeamBus.userSenderId,
          content: 'read user',
          createdAt: 1000,
          read: true,
          seq: 0,
        ),
        _record(
          id: 'unread-1',
          from: TeamBus.userSenderId,
          content: 'queued user',
          createdAt: 2000,
          seq: 1,
        ),
        _record(
          id: 'teammate-1',
          from: 'worker',
          content: 'ignore me',
          createdAt: 3000,
          read: true,
          seq: 2,
        ),
        _record(
          id: 'read-2',
          from: TeamBus.userSenderId,
          content: 'second read',
          createdAt: 4000,
          read: true,
          seq: 3,
        ),
        _record(
          id: 'unread-2',
          from: TeamBus.userSenderId,
          content: 'parked user',
          createdAt: 5000,
          seq: 4,
        ),
      ];

      final part = partitionMailboxUserRecords(records);

      expect(part.unread.map((m) => m.id), ['unread-1', 'unread-2']);
      expect(part.unread[0].content, 'queued user');
      expect(part.unread[1].content, 'parked user');

      expect(part.events, hasLength(2));
      expect(part.events[0].id, 'mailbox:read-1');
      expect(part.events[0].role, AiRole.user);
      expect(part.events[0].parts.single, isA<AiTextPart>());
      expect((part.events[0].parts.single as AiTextPart).text, 'read user');
      expect(part.events[0].source, 'mailbox');
      expect(part.events[0].deliveryChannel, 'mailbox');
      expect(
        part.events[0].createdAt,
        DateTime.fromMillisecondsSinceEpoch(1000),
      );

      expect(part.events[1].id, 'mailbox:read-2');
      expect((part.events[1].parts.single as AiTextPart).text, 'second read');
      expect(
        part.events[1].createdAt,
        DateTime.fromMillisecondsSinceEpoch(4000),
      );
    });

    test('returns empty partitions for no user mail', () {
      final part = partitionMailboxUserRecords([
        _record(
          id: 'teammate-1',
          from: 'worker',
          content: 'ignore',
          createdAt: 1000,
          read: true,
        ),
      ]);

      expect(part.events, isEmpty);
      expect(part.unread, isEmpty);
    });
  });

  group('MailboxUserSource', () {
    test('loads partition for seat via injected loadRecords', () async {
      final source = MailboxUserSource(
        loadRecords: (_) async => [
          _record(
            id: 'mail-1',
            from: TeamBus.userSenderId,
            content: 'hello',
            createdAt: 42,
            read: true,
          ),
          _record(
            id: 'mail-2',
            from: TeamBus.userSenderId,
            content: 'queued',
            createdAt: 99,
          ),
        ],
      );

      final part = await source.load(
        const TimelineSeat(sessionId: 'sess-1', memberId: 'leader'),
      );

      expect(part.events.single.id, 'mailbox:mail-1');
      expect(part.unread.single.id, 'mail-2');
      expect(part.unread.single.content, 'queued');
    });
  });
}
