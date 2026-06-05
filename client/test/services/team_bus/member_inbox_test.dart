import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/cancellation.dart';
import 'package:teampilot/services/team_bus/member_inbox.dart';
import 'package:teampilot/services/team_bus/persistence/in_memory_bus_message_log.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

TeamMessage _msg(String id) => TeamMessage(id: id, from: 'a', to: 'b', content: id);

MemberInbox _inbox() => MemberInbox(memberId: 'm');

void main() {
  test('waitAndTake returns immediately when there is already unread', () {
    fakeAsync((async) {
      final box = _inbox();
      box.deliver(_msg('1'));

      List<TeamMessage>? got;
      box.waitAndTake(timeout: const Duration(seconds: 30)).then((b) => got = b);
      async.flushMicrotasks();

      expect(got!.map((m) => m.id), ['1']);
      expect(box.isEmpty, isTrue); // taken
    });
  });

  test('waitAndTake blocks, then resolves with a debounced batch', () {
    fakeAsync((async) {
      final box = _inbox();
      List<TeamMessage>? got;
      box.waitAndTake(timeout: const Duration(seconds: 30)).then((b) => got = b);
      async.flushMicrotasks();
      expect(got, isNull); // still parked

      box.deliver(_msg('1'));
      box.deliver(_msg('2'));
      async.elapse(const Duration(milliseconds: 50)); // debounce window

      expect(got!.map((m) => m.id), ['1', '2']); // batched
    });
  });

  test('waitAndTake returns an empty batch on timeout', () {
    fakeAsync((async) {
      final box = _inbox();
      List<TeamMessage>? got;
      box.waitAndTake(timeout: const Duration(seconds: 30)).then((b) => got = b);
      async.elapse(const Duration(seconds: 30));

      expect(got, isEmpty);
    });
  });

  test('waitAndTake unblocks on cancel', () {
    fakeAsync((async) {
      final box = _inbox();
      final cancel = CancellationToken();
      List<TeamMessage>? got;
      box.waitAndTake(cancel: cancel).then((b) => got = b);
      async.flushMicrotasks();
      expect(got, isNull);

      cancel.cancel();
      async.flushMicrotasks();
      expect(got, isEmpty);
    });
  });

  test('concurrent waiters do not complete each other (no mutual spin)', () {
    fakeAsync((async) {
      final box = _inbox();
      var a = 0;
      var b = 0;
      // Two overlapping wait_for_message parks on the SAME inbox (e.g. a CLI
      // re-issued wait_for_message before the previous SSE disconnect was
      // detected). Neither should complete the other.
      box.waitForArrival().then((_) => a++);
      box.waitForArrival().then((_) => b++);
      async.flushMicrotasks();
      expect(a, 0, reason: 'parked waiter must not be woken by a second park');
      expect(b, 0);

      // A single delivery wakes both parked waiters exactly once.
      box.deliver(_msg('1'));
      async.elapse(const Duration(milliseconds: 50)); // debounce window
      expect(a, 1);
      expect(b, 1);
    });
  });

  test('re-parking loops on one inbox settle instead of ping-ponging', () {
    fakeAsync((async) {
      final box = _inbox();
      var aLoops = 0;
      var bLoops = 0;
      var stop = false;
      // Simulate two receiveWork-style loops that re-park whenever they wake
      // without consuming (inbox empty). A mutual-completion bug makes these
      // ping-pong forever; the fix keeps them parked.
      void loopA() {
        box.waitForArrival().then((_) {
          aLoops++;
          if (!stop) loopA();
        });
      }

      void loopB() {
        box.waitForArrival().then((_) {
          bLoops++;
          if (!stop) loopB();
        });
      }

      loopA();
      loopB();
      async.flushMicrotasks();
      stop = true; // unwind any in-flight loop before asserting
      async.flushMicrotasks();
      expect(aLoops, 0, reason: 'no delivery yet -> no wakeups -> no spin');
      expect(bLoops, 0);
    });
  });

  test('deliver dedupes by message id', () {
    final box = _inbox();
    box.deliver(_msg('1'));
    box.deliver(_msg('1'));
    expect(box.unreadCount, 1);
  });

  test('peekAll does not consume; take + confirm advances read', () async {
    final box = _inbox()..bindLog(InMemoryBusMessageLog(), () => 0);
    box.deliver(_msg('1'));
    expect(box.peekAll().map((m) => m.id), ['1']);
    expect(box.unreadCount, 1); // peek did not consume

    final taken = await box.waitAndTake();
    expect(taken.map((m) => m.id), ['1']);
    await box.confirmRead(['1']);

    // Confirmed-read messages do not come back after rehydrate.
    final fresh = _inbox()..bindLog(InMemoryBusMessageLog(), () => 0);
    await fresh.rehydrate();
    expect(fresh.unreadCount, 0);
  });

  test('restore re-queues a taken-but-unconfirmed batch', () async {
    final box = _inbox();
    box.deliver(_msg('1'));
    final taken = await box.waitAndTake();
    expect(box.isEmpty, isTrue);

    box.restore(taken);
    expect(box.unreadCount, 1);
    final again = await box.waitAndTake();
    expect(again.map((m) => m.id), ['1']);
  });

  test('rehydrate restores only unread from the log', () async {
    final log = InMemoryBusMessageLog();
    final box = MemberInbox(memberId: 'm')..bindLog(log, () => 0);
    box.deliver(_msg('1'));
    box.deliver(_msg('2'));
    await box.waitAndTake();
    await box.confirmRead(['1']); // 1 read, 2 still taken-unconfirmed (unread)
    await Future<void>.delayed(Duration.zero); // let appends flush

    final restored = MemberInbox(memberId: 'm')..bindLog(log, () => 0);
    await restored.rehydrate();
    expect(restored.peekAll().map((m) => m.id), ['2']);
  });
}
