import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_layout_coordinator.dart';

class _SpyHoldTarget implements PtyResizeHoldTarget {
  int beginCount = 0;
  int endCount = 0;
  bool lastFlush = true;

  @override
  void beginPtyHold() {
    beginCount++;
  }

  @override
  void endPtyHold({bool flush = true}) {
    endCount++;
    lastFlush = flush;
  }
}

void main() {
  group('TerminalLayoutCoordinator', () {
    late TerminalLayoutCoordinator coordinator;
    late _SpyHoldTarget t1, t2;

    setUp(() {
      coordinator = TerminalLayoutCoordinator();
      t1 = _SpyHoldTarget();
      t2 = _SpyHoldTarget();
      coordinator.register(t1);
      coordinator.register(t2);
    });

    tearDown(() {
      coordinator.dispose();
    });

    test('hasTargets reports registered targets', () {
      expect(coordinator.hasTargets, isTrue);
    });

    test('unregister removes target', () {
      coordinator.unregister(t1);
      expect(coordinator.hasTargets, isTrue);
      coordinator.unregister(t2);
      expect(coordinator.hasTargets, isFalse);
    });

    test('runLayoutTransactionSync begins and ends on all targets', () {
      coordinator.runLayoutTransactionSync(() {});
      expect(t1.beginCount, 1);
      expect(t1.endCount, 1);
      expect(t2.beginCount, 1);
      expect(t2.endCount, 1);
    });

    test('runLayoutTransactionSync with flush:false', () {
      coordinator.runLayoutTransactionSync(() {}, flush: false);
      expect(t1.endCount, 1);
      expect(t1.lastFlush, isFalse);
      expect(t2.lastFlush, isFalse);
    });

    test('runLayoutTransactionSync ends even if action throws', () {
      expect(
        () => coordinator.runLayoutTransactionSync(() {
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(t1.endCount, 1);
      expect(t2.endCount, 1);
    });

    test('dispose ends all transactions and clears', () {
      coordinator.dispose();
      expect(t1.endCount, 1);
      expect(t2.endCount, 1);
      expect(coordinator.hasTargets, isFalse);
    });
  });
}
