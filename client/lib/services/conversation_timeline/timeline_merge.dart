import 'package:ai_message_core/ai_message_core.dart';

import 'timeline_models.dart';

final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

int _compareTimelineEvents(TimelineEvent a, TimelineEvent b) {
  final timeCmp = (a.createdAt ?? _epoch).compareTo(b.createdAt ?? _epoch);
  if (timeCmp != 0) return timeCmp;
  final orderCmp = a.cliOrder.compareTo(b.cliOrder);
  if (orderCmp != 0) return orderCmp;
  return a.id.compareTo(b.id);
}

/// Sort by (createdAt ?? epoch, cliOrder, id); missing timestamps keep CLI order via cliOrder.
TimelineSnapshot mergeTimeline({
  required List<TimelineEvent> events,
  required List<UnreadUserMail> unread,
}) {
  final sorted = [...events]..sort(_compareTimelineEvents);

  final deduped = <TimelineEvent>[];
  final seen = <String>{};
  for (var i = sorted.length - 1; i >= 0; i--) {
    final event = sorted[i];
    if (seen.add(event.id)) {
      deduped.add(event);
    }
  }
  deduped.sort(_compareTimelineEvents);

  final messages = [
    for (final event in deduped)
      AiMessage(
        id: event.id,
        role: event.role,
        parts: event.parts,
        createdAt: event.createdAt,
        deliveryChannel: event.deliveryChannel,
      ),
  ];

  return TimelineSnapshot(messages: messages, unreadUserMails: unread);
}

sealed class CliTimelineDelta {
  const CliTimelineDelta();
}

class CliTimelineUnchanged extends CliTimelineDelta {
  const CliTimelineUnchanged();
}

class CliTimelineAppended extends CliTimelineDelta {
  const CliTimelineAppended({required this.events});

  final List<TimelineEvent> events;
}

/// Same-id in-place update of the last CLI message (streaming assistant).
class CliTimelineLastReplaced extends CliTimelineDelta {
  const CliTimelineLastReplaced({required this.message});

  final AiMessage message;
}

/// Last CLI message content changed and the list also grew.
class CliTimelineLastReplacedAndAppended extends CliTimelineDelta {
  const CliTimelineLastReplacedAndAppended({
    required this.message,
    required this.events,
  });

  final AiMessage message;
  final List<TimelineEvent> events;
}

class CliTimelineInvalidated extends CliTimelineDelta {
  const CliTimelineInvalidated();
}

sealed class MailboxTimelineDelta {
  const MailboxTimelineDelta();
}

class MailboxTimelineUnchanged extends MailboxTimelineDelta {
  const MailboxTimelineUnchanged();
}

class MailboxTimelineAppended extends MailboxTimelineDelta {
  const MailboxTimelineAppended({
    required this.events,
    required this.unread,
  });

  final List<TimelineEvent> events;
  final List<UnreadUserMail> unread;
}

class MailboxTimelineInvalidated extends MailboxTimelineDelta {
  const MailboxTimelineInvalidated();
}

TimelineEvent _eventForMessage(AiMessage message, List<AiMessage> cliMessages) {
  if (message.deliveryChannel == 'mailbox') {
    return TimelineEvent(
      id: message.id,
      role: message.role,
      parts: message.parts,
      createdAt: message.createdAt,
      source: 'mailbox',
      deliveryChannel: message.deliveryChannel,
    );
  }
  final cliOrder = cliMessages.indexWhere((m) => m.id == message.id);
  return TimelineEvent(
    id: message.id,
    role: message.role,
    parts: message.parts,
    createdAt: message.createdAt,
    source: 'cli',
    deliveryChannel: message.deliveryChannel,
    cliOrder: cliOrder < 0 ? 0 : cliOrder,
  );
}

AiMessage _messageFromEvent(TimelineEvent event) {
  return AiMessage(
    id: event.id,
    role: event.role,
    parts: event.parts,
    createdAt: event.createdAt,
    deliveryChannel: event.deliveryChannel,
  );
}

int _insertIndexForEvent(
  List<AiMessage> messages,
  TimelineEvent event,
  List<AiMessage> cliMessages,
) {
  for (var i = 0; i < messages.length; i++) {
    final existing = _eventForMessage(messages[i], cliMessages);
    if (_compareTimelineEvents(event, existing) < 0) {
      return i;
    }
  }
  return messages.length;
}

TimelineSnapshot _fullTimelineMerge({
  required List<AiMessage> nextCliMessages,
  required List<TimelineEvent> mailboxEvents,
  required List<UnreadUserMail> unread,
}) {
  final cliEvents = [
    for (var i = 0; i < nextCliMessages.length; i++)
      TimelineEvent(
        id: nextCliMessages[i].id,
        role: nextCliMessages[i].role,
        parts: nextCliMessages[i].parts,
        createdAt: nextCliMessages[i].createdAt,
        source: 'cli',
        deliveryChannel: nextCliMessages[i].deliveryChannel,
        cliOrder: i,
      ),
  ];
  return mergeTimeline(
    events: [...cliEvents, ...mailboxEvents],
    unread: unread,
  );
}

TimelineSnapshot _tryAppendEvents({
  required List<AiMessage> messages,
  required List<TimelineEvent> newEvents,
  required List<AiMessage> nextCliMessages,
  required List<UnreadUserMail> unread,
  required List<TimelineEvent> mailboxEvents,
}) {
  if (newEvents.isEmpty) {
    return TimelineSnapshot(messages: messages, unreadUserMails: unread);
  }
  final existingIds = {for (final m in messages) m.id};
  for (final event in newEvents) {
    if (existingIds.contains(event.id)) {
      return _fullTimelineMerge(
        nextCliMessages: nextCliMessages,
        mailboxEvents: mailboxEvents,
        unread: unread,
      );
    }
  }
  final sorted = [...newEvents]..sort(_compareTimelineEvents);
  for (final event in sorted) {
    final insertAt = _insertIndexForEvent(messages, event, nextCliMessages);
    messages.insert(insertAt, _messageFromEvent(event));
  }
  return TimelineSnapshot(messages: messages, unreadUserMails: unread);
}

/// Identity-preserving merge for append-only CLI/mailbox deltas. Falls back to
/// [mergeTimeline] when order or content is invalidated.
TimelineSnapshot mergeTimelineIncremental({
  required SeatTimelineSnapshot previous,
  required CliTimelineDelta cliDelta,
  required MailboxTimelineDelta mailboxDelta,
  required List<UnreadUserMail> unread,
  required List<AiMessage> nextCliMessages,
  required List<TimelineEvent> mailboxEvents,
}) {
  if (cliDelta is CliTimelineInvalidated ||
      mailboxDelta is MailboxTimelineInvalidated) {
    return _fullTimelineMerge(
      nextCliMessages: nextCliMessages,
      mailboxEvents: mailboxEvents,
      unread: unread,
    );
  }

  if (cliDelta is CliTimelineLastReplaced ||
      cliDelta is CliTimelineLastReplacedAndAppended) {
    final replaced = cliDelta is CliTimelineLastReplaced
        ? cliDelta.message
        : (cliDelta as CliTimelineLastReplacedAndAppended).message;
    final extraCli = cliDelta is CliTimelineLastReplacedAndAppended
        ? cliDelta.events
        : const <TimelineEvent>[];
    final messages = List<AiMessage>.of(previous.snapshot.messages);
    final index = messages.lastIndexWhere((m) => m.id == replaced.id);
    if (index < 0) {
      return _fullTimelineMerge(
        nextCliMessages: nextCliMessages,
        mailboxEvents: mailboxEvents,
        unread: unread,
      );
    }
    messages[index] = replaced;
    final mailboxAppend = switch (mailboxDelta) {
      MailboxTimelineAppended(:final events) => events,
      _ => const <TimelineEvent>[],
    };
    return _tryAppendEvents(
      messages: messages,
      newEvents: [...extraCli, ...mailboxAppend],
      nextCliMessages: nextCliMessages,
      unread: unread,
      mailboxEvents: mailboxEvents,
    );
  }

  final cliAppend = switch (cliDelta) {
    CliTimelineAppended(:final events) => events,
    _ => const <TimelineEvent>[],
  };
  final mailboxAppend = switch (mailboxDelta) {
    MailboxTimelineAppended(:final events) => events,
    _ => const <TimelineEvent>[],
  };

  if (cliAppend.isEmpty && mailboxAppend.isEmpty) {
    if (previous.snapshot.unreadUserMails == unread) {
      return previous.snapshot;
    }
    return TimelineSnapshot(
      messages: previous.snapshot.messages,
      unreadUserMails: unread,
    );
  }

  return _tryAppendEvents(
    messages: List<AiMessage>.from(previous.snapshot.messages),
    newEvents: [...cliAppend, ...mailboxAppend],
    nextCliMessages: nextCliMessages,
    unread: unread,
    mailboxEvents: mailboxEvents,
  );
}
