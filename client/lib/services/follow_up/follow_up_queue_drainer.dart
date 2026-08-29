import '../../pages/chat/history_continue_delivery.dart';
import 'follow_up_queue.dart';
import '../../utils/logging/logger.dart';

final class FollowUpQueueDrainer {
  FollowUpQueueDrainer({
    required this.store,
    required this.deliver,
  });

  final InMemoryFollowUpQueueStore store;
  final Future<HistoryContinueSubmitResult> Function(String seat, String content)
      deliver;

  final _inFlight = <String>{};
  final _lastWorking = <String, bool>{};
  final _pendingIdleDrain = <String>{};

  Future<void> onMemberWorkingChanged(
    String seat, {
    required bool working,
  }) async {
    final prev = _lastWorking[seat];
    _lastWorking[seat] = working;
    if (working) return;
    final missedWhileBusy = _pendingIdleDrain.remove(seat);
    if (prev == true || missedWhileBusy) {
      await _tryDrain(seat);
    }
  }

  Future<void> resumeAndMaybeDrain(String seat) async {
    store.resume(seat);
    if (_lastWorking[seat] == true) return;
    await _tryDrain(seat);
  }

  Future<void> _tryDrain(String seat) async {
    if (_inFlight.contains(seat)) {
      _pendingIdleDrain.add(seat);
      return;
    }
    _inFlight.add(seat);
    try {
      while (true) {
        if (_lastWorking[seat] == true) return;
        final q = store.queueFor(seat);
        if (q.drain != FollowUpDrainMode.armed || q.items.isEmpty) return;
        final head = q.items.first;
        final result = await deliver(seat, head.content);
        if (!result.ok) {
          appLogger.d('follow-up drain failed seat=$seat id=${head.id}');
          return;
        }
        store.remove(seat, head.id);
        // PTY deliver typically latches working before returning — stop and
        // wait for the next idle edge. Mailbox / no-latch paths stay idle so
        // keep draining remaining heads.
        if (_lastWorking[seat] == true) return;
      }
    } finally {
      _inFlight.remove(seat);
      if (_pendingIdleDrain.remove(seat) && _lastWorking[seat] != true) {
        await _tryDrain(seat);
      }
    }
  }
}
