import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/mailbox.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

TeamMessage _msg(String id) => TeamMessage(id: id, from: 'a', to: 'b', content: id);

void main() {
  test('waitBatch returns immediately when queue already has messages', () {
    fakeAsync((async) {
      final box = Mailbox();
      box.deliver(_msg('1'));

      List<TeamMessage>? got;
      box.waitBatch(timeout: const Duration(seconds: 30)).then((b) => got = b);
      async.flushMicrotasks();

      expect(got!.map((m) => m.id), ['1']);
      expect(box.isEmpty, isTrue); // drained
    });
  });

  test('waitBatch blocks, then resolves with a debounced batch on deliver', () {
    fakeAsync((async) {
      final box = Mailbox();
      List<TeamMessage>? got;
      box.waitBatch(timeout: const Duration(seconds: 30)).then((b) => got = b);
      async.flushMicrotasks();
      expect(got, isNull); // still parked

      box.deliver(_msg('1'));
      box.deliver(_msg('2'));
      async.elapse(const Duration(milliseconds: 50)); // debounce window

      expect(got!.map((m) => m.id), ['1', '2']); // batched
    });
  });

  test('waitBatch returns an empty batch on timeout', () {
    fakeAsync((async) {
      final box = Mailbox();
      List<TeamMessage>? got;
      box.waitBatch(timeout: const Duration(seconds: 30)).then((b) => got = b);
      async.elapse(const Duration(seconds: 30));

      expect(got, isEmpty);
    });
  });
}
