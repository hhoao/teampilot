import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/shared_state/hlc.dart';

void main() {
  group('Hlc', () {
    test('compare orders by wall, counter, then node id', () {
      const a = Hlc(wallMillis: 10, counter: 0, nodeId: 'a');
      const b = Hlc(wallMillis: 10, counter: 0, nodeId: 'b');
      const c = Hlc(wallMillis: 10, counter: 1, nodeId: 'a');
      const d = Hlc(wallMillis: 11, counter: 0, nodeId: 'a');

      expect(a.compareTo(b), lessThan(0));
      expect(b.compareTo(a), greaterThan(0));
      expect(c.compareTo(a), greaterThan(0));
      expect(d.compareTo(c), greaterThan(0));
    });

    test('json and wire forms round-trip', () {
      const stamp = Hlc(wallMillis: 42, counter: 3, nodeId: 'phone:1');

      expect(Hlc.fromJson(stamp.toJson())?.toWire(), stamp.toWire());
      expect(Hlc.parse(stamp.toWire())?.toWire(), stamp.toWire());
      expect(Hlc.fromJson(stamp.toWire())?.toWire(), stamp.toWire());
      expect(Hlc.fromJson('not-a-stamp'), isNull);
    });

    test('zero is the identity for max', () {
      const stamp = Hlc(wallMillis: 1, counter: 0, nodeId: 'a');
      expect(Hlc.zero.max(stamp).toWire(), stamp.toWire());
      expect(stamp.max(Hlc.zero).toWire(), stamp.toWire());
    });
  });

  group('HlcClock', () {
    test('is monotonic when the wall clock does not advance', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1000);
      final clock = HlcClock(nodeId: 'a', clock: () => now);

      final first = clock.now();
      final second = clock.now();

      expect(first.wallMillis, 1000);
      expect(first.counter, 0);
      expect(second.wallMillis, 1000);
      expect(second.counter, 1);
      expect(second.compareTo(first), greaterThan(0));
    });

    test('advances the wall clock and resets the counter', () {
      var now = DateTime.fromMillisecondsSinceEpoch(1000);
      final clock = HlcClock(nodeId: 'a', clock: () => now);
      clock.now();
      clock.now();

      now = DateTime.fromMillisecondsSinceEpoch(2000);
      final third = clock.now();

      expect(third.wallMillis, 2000);
      expect(third.counter, 0);
    });

    test('observe returns a stamp greater than both sides', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1000);
      final clock = HlcClock(nodeId: 'a', clock: () => now);
      clock.now();

      const remote = Hlc(wallMillis: 1000, counter: 5, nodeId: 'b');
      final observed = clock.observe(remote);

      expect(observed.compareTo(remote), greaterThan(0));
      expect(observed.nodeId, 'a');
    });
  });
}
