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
