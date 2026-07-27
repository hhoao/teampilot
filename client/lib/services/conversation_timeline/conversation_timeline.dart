import 'package:ai_message_core/ai_message_core.dart';

import '../team_bus/persistence/bus_message_log.dart';
import 'mailbox_user_source.dart';
import 'timeline_merge.dart';
import 'timeline_models.dart';

/// Merges the CLI transcript with mailbox-delivered user turns into one
/// display timeline: CLI messages keep their [cliOrder] (used when
/// [AiMessage.createdAt] is missing); read mailbox user mail is interleaved by
/// [LoggedMessage.createdAt] via [mergeTimeline]. Unread mail never appears in
/// [TimelineSnapshot.messages] — see [TimelineSnapshot.unreadUserMails].
TimelineSnapshot buildConversationTimeline({
  required List<AiMessage> cliMessages,
  required List<LoggedMessage> mailboxRecords,
}) {
  final cliEvents = <TimelineEvent>[
    for (var i = 0; i < cliMessages.length; i++)
      TimelineEvent(
        id: cliMessages[i].id,
        role: cliMessages[i].role,
        parts: cliMessages[i].parts,
        createdAt: cliMessages[i].createdAt,
        source: 'cli',
        deliveryChannel: cliMessages[i].deliveryChannel,
        cliOrder: i,
      ),
  ];

  final mailbox = partitionMailboxUserRecords(mailboxRecords);

  return mergeTimeline(
    events: [...cliEvents, ...mailbox.events],
    unread: mailbox.unread,
  );
}
