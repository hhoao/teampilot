import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_layout_coordinator.dart';

/// A minimal [TerminalResizeController] that records transaction calls
/// without needing a real engine. Used to test [TerminalLayoutCoordinator]
/// in isolation.
class _SpyController implements TerminalResizeController {
  int beginCount = 0;
  int endCount = 0;
  int commitCount = 0;
  bool lastFlush = true;

  @override
  void beginTransaction() {
    beginCount++;
  }

  @override
  void endTransaction({bool flush = true}) {
    endCount++;
    lastFlush = flush;
  }

  @override
  void commitNow() {
    commitCount++;
  }

  @override
  void dispose() {}

  // ── Unused by coordinator ──────────────────────────────────────────────

  @override
  TerminalGrid propose(ViewportQuery query) =>
      const TerminalGrid(80, 24);

  @override
  TerminalGrid get current => const TerminalGrid(80, 24);

  @override
  TerminalGrid? get committed => null;

  @override
  void Function(int cols, int rows)? onPtyResize;
}

void main() {
  group('TerminalLayoutCoordinator', () {
    late TerminalLayoutCoordinator coordinator;
    late _SpyController c1, c2;

    setUp(() {
      coordinator = TerminalLayoutCoordinator();
      c1 = _SpyController();
      c2 = _SpyController();
      coordinator.register(c1);
      coordinator.register(c2);
    });

    tearDown(() {
      coordinator.dispose();
    });

    test('hasControllers reports registered controllers', () {
      expect(coordinator.hasControllers, isTrue);
    });

    test('unregister removes controller', () {
      coordinator.unregister(c1);
      expect(coordinator.hasControllers, isTrue); // c2 still registered
      coordinator.unregister(c2);
      expect(coordinator.hasControllers, isFalse);
    });

    test('runLayoutTransactionSync begins and ends on all controllers', () {
      coordinator.runLayoutTransactionSync(() {});
      expect(c1.beginCount, 1);
      expect(c1.endCount, 1);
      expect(c2.beginCount, 1);
      expect(c2.endCount, 1);
    });

    test('runLayoutTransactionSync with flush:false', () {
      coordinator.runLayoutTransactionSync(() {}, flush: false);
      expect(c1.endCount, 1);
      expect(c1.lastFlush, isFalse);
      expect(c2.lastFlush, isFalse);
    });

    test('runLayoutTransactionSync ends even if action throws', () {
      expect(
        () => coordinator.runLayoutTransactionSync(() {
          throw StateError('boom');
        }),
        throwsStateError,
      );
      // Both controllers were ended (with flush:false on throw)
      expect(c1.endCount, 1);
      expect(c2.endCount, 1);
    });

    test('flushAllImmediate calls commitNow on all', () {
      coordinator.flushAllImmediate();
      expect(c1.commitCount, 1);
      expect(c2.commitCount, 1);
    });

    test('dispose ends all transactions and clears', () {
      coordinator.dispose();
      // Controllers were ended (flush:false from cancelAllTransactions)
      expect(c1.endCount, 1);
      expect(c2.endCount, 1);
      expect(coordinator.hasControllers, isFalse);
    });
  });
}
