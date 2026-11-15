import 'dart:async';

import 'attention_batch.dart';
import 'attention_cursor.dart';
import 'attention_cursor_store.dart';
import 'attention_event.dart';

/// Thrown when an attention cursor cannot be persisted durably.
///
/// Callers must not ack or advance past the last durable cursor after this.
final class AttentionPersistenceException implements Exception {
  const AttentionPersistenceException(this.message);
  final String message;

  @override
  String toString() => 'AttentionPersistenceException: $message';
}

/// Client-side consumer of an authority attention log.
///
/// [ingest] is deliberately serialized by the caller (the protocol controller
/// awaits it before acking). It deduplicates by [AttentionEvent.eventId],
/// persists the highest consumed seq per home, and only then emits [fresh].
/// A persistence failure throws [AttentionPersistenceException] and leaves the
/// durable cursor unchanged.
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
    final ordered = events.toList()..sort((a, b) => a.seq.compareTo(b.seq));
    if (ordered.isEmpty) return;
    final existing = store.cursorFor(homeId);
    var cursor = existing;
    final accepted = <AttentionEvent>[];
    final batchSeen = <String>{};
    for (final event in ordered) {
      if (!batchSeen.add(event.eventId)) continue;
      if (!store.isSuppressed(event, cursor: existing)) accepted.add(event);
      cursor = cursor?.advance(event) ??
          AttentionCursor(
            authorityId: event.authorityId,
            epoch: event.epoch,
            seq: event.seq,
          );
    }
    if (cursor != null) {
      final ok = await store.remember(
        homeId,
        cursor,
        accepted.map((event) => event.eventId),
      );
      if (!ok) {
        throw const AttentionPersistenceException(
          'failed to persist attention cursor',
        );
      }
    }
    final now = _clock().toUtc();
    for (final event in accepted) {
      if (event.isExpiredAt(now)) continue;
      if (!_fresh.isClosed) _fresh.add(event);
    }
  }

  /// Advances past a range the authority no longer retains. Does not emit.
  ///
  /// Rejects stale older-epoch batches for the same authority and throws
  /// [AttentionPersistenceException] when the cursor cannot be persisted.
  Future<void> skipGap(String homeId, AttentionBatch batch) async {
    assert(batch.gap, 'skipGap requires a gap batch');
    final existing = store.cursorFor(homeId);
    if (existing != null) {
      if (existing.authorityId == batch.authorityId) {
        if (batch.epoch < existing.epoch) return;
        if (existing.epoch == batch.epoch && existing.seq >= batch.toSeq) {
          return;
        }
      }
    }
    final ok = await store.remember(
      homeId,
      AttentionCursor(
        authorityId: batch.authorityId,
        epoch: batch.epoch,
        seq: batch.toSeq,
      ),
      const [],
    );
    if (!ok) {
      throw const AttentionPersistenceException(
        'failed to persist attention gap cursor',
      );
    }
  }

  Future<bool> clearCursor(String homeId) => store.clearCursor(homeId);

  Future<void> dispose() async {
    if (!_fresh.isClosed) await _fresh.close();
  }
}
