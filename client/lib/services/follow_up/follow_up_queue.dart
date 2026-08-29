import 'dart:async';

import 'package:uuid/uuid.dart';

String followUpSeatKey(String sessionId, String memberId) =>
    '${sessionId.trim()}:${memberId.trim()}';

(String sessionId, String memberId)? parseFollowUpSeatKey(String seat) {
  final i = seat.indexOf(':');
  if (i <= 0 || i >= seat.length - 1) return null;
  return (seat.substring(0, i), seat.substring(i + 1));
}

final class FollowUpQueuedMessage {
  const FollowUpQueuedMessage({required this.id, required this.content});
  final String id;
  final String content;
}

enum FollowUpDrainMode { armed, paused }

final class FollowUpQueue {
  const FollowUpQueue({
    this.items = const [],
    this.drain = FollowUpDrainMode.armed,
  });
  final List<FollowUpQueuedMessage> items;
  final FollowUpDrainMode drain;

  FollowUpQueue copyWith({
    List<FollowUpQueuedMessage>? items,
    FollowUpDrainMode? drain,
  }) => FollowUpQueue(
    items: items ?? this.items,
    drain: drain ?? this.drain,
  );
}

final class InMemoryFollowUpQueueStore {
  final _queues = <String, FollowUpQueue>{};
  final _controllers = <String, StreamController<FollowUpQueue>>{};
  final _uuid = const Uuid();

  Iterable<String> get seats => _queues.keys;

  FollowUpQueue queueFor(String seat) =>
      _queues[seat] ?? const FollowUpQueue();

  Stream<FollowUpQueue> watch(String seat) {
    final c = _controllers.putIfAbsent(
      seat,
      () => StreamController<FollowUpQueue>.broadcast(),
    );
    return Stream.multi((multi) {
      multi.add(queueFor(seat));
      final sub = c.stream.listen(multi.add, onError: multi.addError);
      multi.onCancel = sub.cancel;
    });
  }

  void enqueue(String seat, String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    final q = queueFor(seat);
    // Stop may have paused an empty seat; the first new item should auto-drain
    // again. Pausing with items still in the queue keeps paused.
    final drain = q.items.isEmpty
        ? FollowUpDrainMode.armed
        : q.drain;
    _emit(
      seat,
      q.copyWith(
        items: [
          ...q.items,
          FollowUpQueuedMessage(id: _uuid.v4(), content: trimmed),
        ],
        drain: drain,
      ),
    );
  }

  void edit(String seat, String id, String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      remove(seat, id);
      return;
    }
    final q = queueFor(seat);
    _emit(
      seat,
      q.copyWith(
        items: [
          for (final m in q.items)
            if (m.id == id) FollowUpQueuedMessage(id: id, content: trimmed) else m,
        ],
      ),
    );
  }

  void moveUp(String seat, String id) {
    final q = queueFor(seat);
    final i = q.items.indexWhere((m) => m.id == id);
    if (i <= 0) return;
    final next = [...q.items];
    final tmp = next[i - 1];
    next[i - 1] = next[i];
    next[i] = tmp;
    _emit(seat, q.copyWith(items: next));
  }

  void remove(String seat, String id) {
    final q = queueFor(seat);
    _emit(
      seat,
      q.copyWith(items: [for (final m in q.items) if (m.id != id) m]),
    );
  }

  void pause(String seat) {
    final q = queueFor(seat);
    // Do not stamp paused onto an empty seat — Stop-while-starting would
    // otherwise poison later follow-ups so they never auto-drain.
    if (q.items.isEmpty) return;
    _emit(seat, q.copyWith(drain: FollowUpDrainMode.paused));
  }

  void resume(String seat) =>
      _emit(seat, queueFor(seat).copyWith(drain: FollowUpDrainMode.armed));

  void clearSeat(String seat) {
    _queues.remove(seat);
    _controllers[seat]?.add(const FollowUpQueue());
  }

  void clearSession(String sessionId) {
    final prefix = '${sessionId.trim()}:';
    final keys = _queues.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in keys) {
      clearSeat(k);
    }
  }

  void _emit(String seat, FollowUpQueue q) {
    _queues[seat] = q;
    _controllers[seat]?.add(q);
  }
}
