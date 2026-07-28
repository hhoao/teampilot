import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/services/follow_up/follow_up_queue.dart';
import 'package:teampilot/services/follow_up/follow_up_queue_drainer.dart';

void main() {
  late InMemoryFollowUpQueueStore store;
  late List<String> delivered;
  late FollowUpQueueDrainer drainer;
  final seat = followUpSeatKey('s1', 'm1');

  setUp(() {
    store = InMemoryFollowUpQueueStore();
    delivered = [];
    drainer = FollowUpQueueDrainer(
      store: store,
      deliver: (s, text) async {
        delivered.add('$s::$text');
        return const HistoryContinueSubmitResult(
          ok: true,
          channel: HistoryContinueChannel.pty,
        );
      },
    );
  });

  test('idle edge drains one head then removes', () async {
    store.enqueue(seat, 'one');
    store.enqueue(seat, 'two');
    drainer.onMemberWorkingChanged(seat, working: true);
    await drainer.onMemberWorkingChanged(seat, working: false);
    expect(delivered, ['$seat::one']);
    expect(store.queueFor(seat).items.map((e) => e.content), ['two']);
  });

  test('paused blocks drain until resume', () async {
    store.enqueue(seat, 'one');
    store.pause(seat);
    await drainer.onMemberWorkingChanged(seat, working: false);
    expect(delivered, isEmpty);
    await drainer.resumeAndMaybeDrain(seat);
    expect(delivered, ['$seat::one']);
    expect(store.queueFor(seat).items, isEmpty);
  });

  test('failed deliver leaves head', () async {
    drainer = FollowUpQueueDrainer(
      store: store,
      deliver: (_, __) async => const HistoryContinueSubmitResult.failed(),
    );
    store.enqueue(seat, 'keep');
    await drainer.onMemberWorkingChanged(seat, working: false);
    expect(store.queueFor(seat).items.single.content, 'keep');
  });
}
