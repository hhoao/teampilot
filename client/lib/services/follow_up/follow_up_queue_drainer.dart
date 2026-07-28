import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/services/follow_up/follow_up_queue.dart';
import 'package:teampilot/utils/logging/logger.dart';

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

  Future<void> onMemberWorkingChanged(
    String seat, {
    required bool working,
  }) async {
    final prev = _lastWorking[seat];
    _lastWorking[seat] = working;
    if (working) return;
    if (prev == true) {
      await _tryDrain(seat);
    }
  }

  Future<void> resumeAndMaybeDrain(String seat) async {
    store.resume(seat);
    if (_lastWorking[seat] == true) return;
    await _tryDrain(seat);
  }

  Future<void> _tryDrain(String seat) async {
    if (_inFlight.contains(seat)) return;
    final q = store.queueFor(seat);
    if (q.drain != FollowUpDrainMode.armed || q.items.isEmpty) return;
    final head = q.items.first;
    _inFlight.add(seat);
    try {
      final result = await deliver(seat, head.content);
      if (result.ok) {
        store.remove(seat, head.id);
      } else {
        appLogger.d('follow-up drain failed seat=$seat id=${head.id}');
      }
    } finally {
      _inFlight.remove(seat);
    }
  }
}
