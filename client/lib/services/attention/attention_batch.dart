import 'attention_event.dart';

/// One `events` wire frame: a contiguous (or explicitly gapped) slice of the
/// authority log.
final class AttentionBatch {
  const AttentionBatch({
    required this.authorityId,
    required this.epoch,
    required this.fromSeq,
    required this.toSeq,
    required this.events,
    this.gap = false,
  });

  final String authorityId;
  final int epoch;
  final int fromSeq;
  final int toSeq;
  final List<AttentionEvent> events;

  /// True when the requested cursor was older than the retained window; the
  /// client accepts [events] but knows some history is unrecoverable.
  final bool gap;

  Map<String, Object?> toJson() => {
    'authority': authorityId,
    'epoch': epoch,
    'fromSeq': fromSeq,
    'toSeq': toSeq,
    'events': [for (final event in events) event.toJson()],
    'gap': gap,
  };

  static AttentionBatch? fromJson(Object? json) {
    if (json is! Map) return null;
    final authority = json['authority'];
    final epoch = json['epoch'];
    final fromSeq = json['fromSeq'];
    final toSeq = json['toSeq'];
    final gap = json['gap'];
    if (authority is! String || authority.isEmpty) return null;
    final events = <AttentionEvent>[];
    var invalid = false;
    final rawEvents = json['events'];
    if (rawEvents is List) {
      for (final raw in rawEvents) {
        final event = AttentionEvent.fromJson(raw);
        if (event != null) {
          events.add(event);
        } else {
          invalid = true;
        }
      }
    }
    return AttentionBatch(
      authorityId: authority,
      epoch: epoch is num ? epoch.toInt() : 0,
      fromSeq: fromSeq is num ? fromSeq.toInt() : 0,
      toSeq: toSeq is num ? toSeq.toInt() : 0,
      events: events,
      // A dropped entry means the batch is no longer contiguous.
      gap: (gap is bool && gap) || invalid,
    );
  }
}
