import 'package:ai_message_core/ai_message_core.dart';

import '../team_bus/persistence/bus_message_log.dart';
import '../team_bus/team_bus.dart';
import 'timeline_models.dart';

/// Splits mailbox log records into timeline body events (read user mail) and
/// unread user mail (queued / parked).
({List<TimelineEvent> events, List<UnreadUserMail> unread})
partitionMailboxUserRecords(List<LoggedMessage> records) {
  final events = <TimelineEvent>[];
  final unread = <UnreadUserMail>[];

  for (final record in records) {
    if (record.message.from != TeamBus.userSenderId) continue;
    if (record.read) {
      events.add(
        TimelineEvent(
          id: 'mailbox:${record.message.id}',
          role: AiRole.user,
          parts: [AiTextPart(text: record.message.content)],
          createdAt: DateTime.fromMillisecondsSinceEpoch(record.createdAt),
          source: 'mailbox',
          deliveryChannel: 'mailbox',
        ),
      );
    } else {
      unread.add(
        UnreadUserMail(
          id: record.message.id,
          content: record.message.content,
        ),
      );
    }
  }

  return (events: events, unread: unread);
}

class MailboxUserSource {
  MailboxUserSource({required this.loadRecords});

  final Future<List<LoggedMessage>> Function(String memberId) loadRecords;

  Future<({List<TimelineEvent> events, List<UnreadUserMail> unread})> load(
    TimelineSeat seat,
  ) async {
    final records = await loadRecords(seat.memberId);
    return partitionMailboxUserRecords(records);
  }
}
