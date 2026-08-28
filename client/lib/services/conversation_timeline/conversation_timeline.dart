import 'package:ai_message_core/ai_message_core.dart';

import '../team_bus/persistence/bus_message_log.dart';
import '../team_bus/team_bus.dart';
import 'mailbox_user_source.dart';
import 'timeline_merge.dart';
import 'timeline_models.dart';

TimelineEvent _cliMessageToEvent(AiMessage message, {required int cliOrder}) {
  return TimelineEvent(
    id: message.id,
    role: message.role,
    parts: message.parts,
    createdAt: message.createdAt,
    source: 'cli',
    deliveryChannel: message.deliveryChannel,
    cliOrder: cliOrder,
  );
}

TimelineEvent _mailboxRecordToEvent(LoggedMessage record) {
  return TimelineEvent(
    id: 'mailbox:${record.message.id}',
    role: AiRole.user,
    parts: [AiTextPart(text: record.message.content)],
    createdAt: DateTime.fromMillisecondsSinceEpoch(record.createdAt),
    source: 'mailbox',
    deliveryChannel: 'mailbox',
  );
}

List<TimelineEvent> _cliEventsFromMessages(List<AiMessage> cliMessages) {
  return [
    for (var i = 0; i < cliMessages.length; i++)
      _cliMessageToEvent(cliMessages[i], cliOrder: i),
  ];
}

/// Compares CLI transcripts for append-only growth vs rewrite.
///
/// Unchanged prefix messages that are the same instance skip content
/// fingerprints. A same-id content change on the last message is
/// [CliTimelineLastReplaced] instead of invalidating the whole timeline.
CliTimelineDelta computeCliTimelineDelta({
  required List<AiMessage> previous,
  required List<AiMessage> next,
}) {
  if (identical(previous, next)) return const CliTimelineUnchanged();
  if (next.length < previous.length) return const CliTimelineInvalidated();
  var lastReplaced = false;
  for (var i = 0; i < previous.length; i++) {
    if (identical(previous[i], next[i])) continue;
    if (previous[i].id != next[i].id) return const CliTimelineInvalidated();
    if (messagesCheapEqual(previous[i], next[i])) {
      continue;
    }
    if (i == previous.length - 1) {
      lastReplaced = true;
      continue;
    }
    return const CliTimelineInvalidated();
  }
  if (lastReplaced) {
    if (next.length != previous.length) {
      return const CliTimelineInvalidated();
    }
    return CliTimelineLastReplaced(message: next.last);
  }
  if (next.length == previous.length) return const CliTimelineUnchanged();
  return CliTimelineAppended(
    events: [
      for (var i = previous.length; i < next.length; i++)
        _cliMessageToEvent(next[i], cliOrder: i),
    ],
  );
}

/// Compares mailbox records for append / read promotion vs rewrite.
MailboxTimelineDelta computeMailboxTimelineDelta({
  required List<LoggedMessage> previous,
  required List<LoggedMessage> next,
}) {
  if (identical(previous, next)) return const MailboxTimelineUnchanged();
  if (next.length < previous.length) return const MailboxTimelineInvalidated();

  final newEvents = <TimelineEvent>[];
  final shared = previous.length < next.length ? previous.length : next.length;
  for (var i = 0; i < shared; i++) {
    if (previous[i].seq != next[i].seq) {
      return const MailboxTimelineInvalidated();
    }
    if (previous[i].read == next[i].read) continue;
    if (!previous[i].read && next[i].read) {
      if (next[i].message.from == TeamBus.userSenderId) {
        newEvents.add(_mailboxRecordToEvent(next[i]));
      }
      continue;
    }
    return const MailboxTimelineInvalidated();
  }

  for (var i = previous.length; i < next.length; i++) {
    final record = next[i];
    if (record.read && record.message.from == TeamBus.userSenderId) {
      newEvents.add(_mailboxRecordToEvent(record));
    }
  }

  final partition = partitionMailboxUserRecords(next);
  if (newEvents.isEmpty && next.length == previous.length) {
    return const MailboxTimelineUnchanged();
  }
  return MailboxTimelineAppended(
    events: newEvents,
    unread: partition.unread,
  );
}

/// Merges the CLI transcript with mailbox-delivered user turns into one
/// display timeline: CLI messages keep their [cliOrder] (used when
/// [AiMessage.createdAt] is missing); read mailbox user mail is interleaved by
/// [LoggedMessage.createdAt] via [mergeTimeline]. Unread mail never appears in
/// [TimelineSnapshot.messages] — see [TimelineSnapshot.unreadUserMails].
TimelineSnapshot buildConversationTimeline({
  required List<AiMessage> cliMessages,
  required List<LoggedMessage> mailboxRecords,
}) {
  final cliEvents = _cliEventsFromMessages(cliMessages);
  final mailbox = partitionMailboxUserRecords(mailboxRecords);

  return mergeTimeline(
    events: [...cliEvents, ...mailbox.events],
    unread: mailbox.unread,
  );
}

/// Cached incremental merge when CLI/mailbox deltas are append-only; otherwise
/// falls back to [buildConversationTimeline].
SeatTimelineSnapshot buildConversationTimelineIncremental({
  SeatTimelineSnapshot? previous,
  required List<AiMessage> cliMessages,
  required List<LoggedMessage> mailboxRecords,
}) {
  final mailbox = partitionMailboxUserRecords(mailboxRecords);

  if (previous == null) {
    final allEvents = [
      ..._cliEventsFromMessages(cliMessages),
      ...mailbox.events,
    ];
    return SeatTimelineSnapshot(
      cliMessages: cliMessages,
      mailboxRecords: mailboxRecords,
      snapshot: mergeTimeline(events: allEvents, unread: mailbox.unread),
    );
  }

  final cliDelta = computeCliTimelineDelta(
    previous: previous.cliMessages,
    next: cliMessages,
  );
  final mailboxDelta = computeMailboxTimelineDelta(
    previous: previous.mailboxRecords,
    next: mailboxRecords,
  );

  if (cliDelta is CliTimelineUnchanged &&
      mailboxDelta is MailboxTimelineUnchanged &&
      identical(cliMessages, previous.cliMessages) &&
      identical(mailboxRecords, previous.mailboxRecords)) {
    return previous;
  }

  final skipAllEvents =
      cliDelta is CliTimelineLastReplaced &&
      mailboxDelta is MailboxTimelineUnchanged;
  final allEvents = skipAllEvents
      ? const <TimelineEvent>[]
      : [
          ..._cliEventsFromMessages(cliMessages),
          ...mailbox.events,
        ];

  final snapshot = mergeTimelineIncremental(
    previous: previous,
    cliDelta: cliDelta,
    mailboxDelta: mailboxDelta,
    allEvents: allEvents,
    unread: mailbox.unread,
    nextCliMessages: cliMessages,
  );

  return SeatTimelineSnapshot(
    cliMessages: cliMessages,
    mailboxRecords: mailboxRecords,
    snapshot: snapshot,
  );
}
