import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/follow_up/follow_up_queue.dart';

void main() {
  late InMemoryFollowUpQueueStore store;

  setUp(() {
    store = InMemoryFollowUpQueueStore();
  });

  test('enqueue appends and watch emits', () async {
    final seat = followUpSeatKey('s1', 'm1');
    final events = <FollowUpQueue>[];
    final sub = store.watch(seat).listen(events.add);

    store.enqueue(seat, 'a');
    store.enqueue(seat, 'b');
    await Future<void>.delayed(Duration.zero);

    expect(store.queueFor(seat).items.map((e) => e.content), ['a', 'b']);
    expect(events.last.items.map((e) => e.content), ['a', 'b']);
    await sub.cancel();
  });

  test('edit empty removes; moveUp swaps with previous', () {
    final seat = followUpSeatKey('s1', 'm1');
    store.enqueue(seat, 'a');
    store.enqueue(seat, 'b');
    final idB = store.queueFor(seat).items[1].id;
    store.moveUp(seat, idB);
    expect(store.queueFor(seat).items.map((e) => e.content), ['b', 'a']);
    store.edit(seat, store.queueFor(seat).items.first.id, '   ');
    expect(store.queueFor(seat).items.map((e) => e.content), ['a']);
  });

  test('pause and resume toggle drain without dropping items', () {
    final seat = followUpSeatKey('s1', 'm1');
    store.enqueue(seat, 'x');
    store.pause(seat);
    expect(store.queueFor(seat).drain, FollowUpDrainMode.paused);
    expect(store.queueFor(seat).items, hasLength(1));
    store.resume(seat);
    expect(store.queueFor(seat).drain, FollowUpDrainMode.armed);
  });

  test('pause on empty seat does not stick paused onto later enqueues', () {
    final seat = followUpSeatKey('s1', 'm1');
    store.pause(seat);
    store.enqueue(seat, 'later');
    expect(store.queueFor(seat).drain, FollowUpDrainMode.armed);
    expect(store.queueFor(seat).items.single.content, 'later');
  });

  test('enqueue onto empty paused seat re-arms drain', () {
    final seat = followUpSeatKey('s1', 'm1');
    store.enqueue(seat, 'x');
    store.pause(seat);
    store.remove(seat, store.queueFor(seat).items.single.id);
    expect(store.queueFor(seat).items, isEmpty);
    expect(store.queueFor(seat).drain, FollowUpDrainMode.paused);
    store.enqueue(seat, 'fresh');
    expect(store.queueFor(seat).drain, FollowUpDrainMode.armed);
  });

  test('clearSession drops all seats for that session', () {
    store.enqueue(followUpSeatKey('s1', 'm1'), 'a');
    store.enqueue(followUpSeatKey('s1', 'm2'), 'b');
    store.enqueue(followUpSeatKey('s2', 'm1'), 'c');
    store.clearSession('s1');
    expect(store.queueFor(followUpSeatKey('s1', 'm1')).items, isEmpty);
    expect(store.queueFor(followUpSeatKey('s1', 'm2')).items, isEmpty);
    expect(store.queueFor(followUpSeatKey('s2', 'm1')).items, hasLength(1));
  });
}
