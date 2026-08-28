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

/// Identity-preserving merge for append-only CLI/mailbox deltas. Falls back to
/// [mergeTimeline] when order or content is invalidated.
TimelineSnapshot mergeTimelineIncremental({
  required SeatTimelineSnapshot previous,
  required CliTimelineDelta cliDelta,
  required MailboxTimelineDelta mailboxDelta,
  required List<TimelineEvent> allEvents,
  required List<UnreadUserMail> unread,
  required List<AiMessage> nextCliMessages,
}) {
  if (cliDelta is CliTimelineInvalidated ||
      mailboxDelta is MailboxTimelineInvalidated) {
    return mergeTimeline(events: allEvents, unread: unread);
  }

  if (cliDelta is CliTimelineLastReplaced) {
    if (mailboxDelta is MailboxTimelineAppended) {
      return mergeTimeline(events: allEvents, unread: unread);
    }
    final messages = List<AiMessage>.of(previous.snapshot.messages);
    final index = messages.lastIndexWhere((m) => m.id == cliDelta.message.id);
    if (index < 0) {
      return mergeTimeline(events: allEvents, unread: unread);
    }
    messages[index] = cliDelta.message;
    return TimelineSnapshot(messages: messages, unreadUserMails: unread);
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

  final existingIds = {for (final m in previous.snapshot.messages) m.id};
  for (final event in [...cliAppend, ...mailboxAppend]) {
    if (existingIds.contains(event.id)) {
      return mergeTimeline(events: allEvents, unread: unread);
    }
  }

  var messages = List<AiMessage>.from(previous.snapshot.messages);
  final newEvents = [...cliAppend, ...mailboxAppend]
    ..sort(_compareTimelineEvents);

  for (final event in newEvents) {
    final insertAt = _insertIndexForEvent(messages, event, nextCliMessages);
    messages.insert(insertAt, _messageFromEvent(event));
  }

  final full = mergeTimeline(events: allEvents, unread: unread);
  if (full.messages.length != messages.length ||
      !_sameMessageIds(full.messages, messages)) {
    return full;
  }

  return TimelineSnapshot(messages: messages, unreadUserMails: unread);
}

bool _sameMessageIds(List<AiMessage> a, List<AiMessage> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id) return false;
  }
  return true;
}
