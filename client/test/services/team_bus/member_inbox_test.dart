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
