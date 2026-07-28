import 'dart:async';

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
    var deliverAttempts = 0;
    drainer = FollowUpQueueDrainer(
      store: store,
      deliver: (_, __) async {
        deliverAttempts++;
        return const HistoryContinueSubmitResult.failed();
      },
    );
    store.enqueue(seat, 'keep');
    drainer.onMemberWorkingChanged(seat, working: true);
    await drainer.onMemberWorkingChanged(seat, working: false);
    expect(deliverAttempts, 1);
    expect(store.queueFor(seat).items.single.content, 'keep');
  });

  test('in-flight prevents concurrent second drain', () async {
    final deliverStarted = Completer<void>();
    final releaseDeliver = Completer<void>();
    var deliverAttempts = 0;

    drainer = FollowUpQueueDrainer(
      store: store,
      deliver: (s, text) async {
        deliverAttempts++;
        deliverStarted.complete();
        await releaseDeliver.future;
        delivered.add('$s::$text');
        return const HistoryContinueSubmitResult(
          ok: true,
          channel: HistoryContinueChannel.pty,
        );
      },
    );

    store.enqueue(seat, 'one');
    store.enqueue(seat, 'two');

    drainer.onMemberWorkingChanged(seat, working: true);
    final firstDrain = drainer.onMemberWorkingChanged(seat, working: false);
    await deliverStarted.future;

    drainer.onMemberWorkingChanged(seat, working: true);
    final secondDrain = drainer.onMemberWorkingChanged(seat, working: false);
    await Future<void>.delayed(Duration.zero);
    expect(deliverAttempts, 1);
    expect(delivered, isEmpty);

    releaseDeliver.complete();
    await firstDrain;
    await secondDrain;

    expect(deliverAttempts, 1);
    expect(delivered, ['$seat::one']);
    expect(store.queueFor(seat).items.map((e) => e.content), ['two']);
  });
}
