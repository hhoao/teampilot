import 'package:ai_message_core/ai_message_core.dart';

import '../team_bus/persistence/bus_message_log.dart';

class TimelineSeat {
  const TimelineSeat({required this.sessionId, required this.memberId});

  final String sessionId;
  final String memberId;
}

class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.role,
    required this.parts,
    this.createdAt,
    required this.source,
    this.deliveryChannel,
    this.cliOrder = 0,
  });

  final String id;
  final AiRole role;
  final List<AiMessagePart> parts;
  final DateTime? createdAt;
  final String source;
  final String? deliveryChannel;
  final int cliOrder;
}

class UnreadUserMail {
  const UnreadUserMail({required this.id, required this.content});

  final String id;
  final String content;
}

class TimelineSnapshot {
  const TimelineSnapshot({
    required this.messages,
    this.unreadUserMails = const [],
  });

  final List<AiMessage> messages;
  final List<UnreadUserMail> unreadUserMails;
}

/// Cached seat timeline: CLI list identity, mailbox records, merged output.
class SeatTimelineSnapshot {
  const SeatTimelineSnapshot({
    required this.cliMessages,
    required this.mailboxRecords,
    required this.snapshot,
  });

  /// Instance identity of the CLI transcript used for this merge.
  final List<AiMessage> cliMessages;
  final List<LoggedMessage> mailboxRecords;
  final TimelineSnapshot snapshot;
}
