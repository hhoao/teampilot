import 'dart:async';

import 'attention_batch.dart';
import 'attention_cursor.dart';
import 'attention_cursor_store.dart';
import 'attention_event.dart';

/// Client-side consumer of an authority attention log.
///
/// [ingest] is deliberately serialized by the caller (the protocol controller
/// awaits it before acking). It deduplicates by [AttentionEvent.eventId],
/// persists the highest consumed seq per home, and only then emits [fresh].
final class AttentionInbox {
  AttentionInbox({
    required this.store,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AttentionCursorStore store;
  final DateTime Function() _clock;
  final StreamController<AttentionEvent> _fresh =
      StreamController<AttentionEvent>.broadcast();

  Stream<AttentionEvent> get fresh => _fresh.stream;

  AttentionCursor? cursorFor(String homeId) => store.cursorFor(homeId);

  Future<void> ingest(String homeId, Iterable<AttentionEvent> events) async {
    final ordered = events.toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    if (ordered.isEmpty) return;
    var cursor = store.cursorFor(homeId);
    final accepted = <AttentionEvent>[];
    final batchSeen = <String>{};
    for (final event in ordered) {
      if (!batchSeen.add(event.eventId)) continue;
      if (!store.hasSeen(event.eventId)) accepted.add(event);
      cursor = cursor?.advance(event) ??
          AttentionCursor(
            authorityId: event.authorityId,
            epoch: event.epoch,
            seq: event.seq,
          );
    }
    if (cursor != null) {
      await store.remember(
        homeId,
        cursor,
        accepted.map((event) => event.eventId),
      );
    }
    final now = _clock().toUtc();
    for (final event in accepted) {
      if (event.isExpiredAt(now)) continue;
      if (!_fresh.isClosed) _fresh.add(event);
    }
  }

  /// Advances past a range the authority no longer retains. Does not emit.
  Future<void> skipGap(String homeId, AttentionBatch batch) async {
    final existing = store.cursorFor(homeId);
    if (existing != null &&
        existing.authorityId == batch.authorityId &&
        existing.epoch == batch.epoch &&
        existing.seq >= batch.toSeq) {
      return;
    }
    await store.remember(
      homeId,
      AttentionCursor(
        authorityId: batch.authorityId,
        epoch: batch.epoch,
        seq: batch.toSeq,
      ),
      const [],
    );
  }

  Future<void> clearCursor(String homeId) => store.clearCursor(homeId);

  Future<void> dispose() async {
    if (!_fresh.isClosed) await _fresh.close();
  }
}
