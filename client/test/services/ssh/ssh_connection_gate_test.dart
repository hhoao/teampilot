import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/ssh_connection_gate.dart';

void main() {
  group('SshConnectionGate', () {
    late SshConnectionGate gate;

    setUp(() {
      gate = SshConnectionGate();
    });

    test('an unknown profile allows its first dial', () {
      expect(gate.stateOf('p1'), SshConnectionGateState.idle);
      expect(() => gate.beforeIo('p1'), returnsNormally);
    });

    test('a down profile rejects I/O until the coordinator rearms it', () {
      gate.markDown('p1');
      expect(
        () => gate.beforeIo('p1'),
        throwsA(isA<SshProfileDownException>()),
      );

      gate.allowNextDial('p1');
      expect(() => gate.beforeIo('p1'), returnsNormally);
      expect(gate.stateOf('p1'), SshConnectionGateState.connecting);
    });

    test('markUp releases waiters and accepts I/O', () async {
      gate.markDown('p1');
      var done = false;
      unawaited(gate.waitUntilUp('p1').then((_) => done = true));
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      expect(gate.hasWaiters('p1'), isTrue);

      gate.markUp('p1');
      await gate.waitUntilUp('p1');

      expect(done, isTrue);
      expect(gate.hasWaiters('p1'), isFalse);
      expect(gate.isUp('p1'), isTrue);
      expect(() => gate.beforeIo('p1'), returnsNormally);
    });

    test('a waiter asks the coordinator for demand', () async {
      final demanded = <String>[];
      gate.onWaiter = demanded.add;

      final waiter = gate.waitUntilUp('p1');
      expect(demanded, ['p1']);

      gate.markUp('p1');
      await waiter;
      expect(gate.hasWaiters('p1'), isFalse);
    });

    test('a suspended profile never dials until resumed', () {
      gate.suspend('p1');
      expect(
        () => gate.beforeIo('p1'),
        throwsA(isA<SshProfileDownException>()),
      );

      gate.resume('p1');
      expect(() => gate.beforeIo('p1'), returnsNormally);
    });

    test('allowNextDial bypasses a down profile', () {
      gate.markDown('p1');
      gate.allowNextDial('p1');

      expect(() => gate.beforeIo('p1'), returnsNormally);
      expect(gate.stateOf('p1'), SshConnectionGateState.connecting);
    });

    test('allowNextDial cannot bypass a suspension', () {
      gate.suspend('p1');
      gate.allowNextDial('p1');

      expect(
        () => gate.beforeIo('p1'),
        throwsA(isA<SshProfileDownException>()),
      );
    });

    test('a late success does not clear a suspension', () {
      gate.suspend('p1');
      gate.markUp('p1');

      expect(gate.stateOf('p1'), SshConnectionGateState.suspended);
    });

    test('a suspension fails waiting consumers', () async {
      final waiter = gate.waitUntilUp('p1');
      gate.suspend('p1');

      await expectLater(waiter, throwsA(isA<SshProfileDownException>()));
      expect(gate.hasWaiters('p1'), isFalse);
    });

    test('the first down transition asks the coordinator to retry', () {
      final downs = <String>[];
      gate.onDown = downs.add;

      gate.markDown('p1');
      gate.markDown('p1');

      expect(downs, ['p1']);

      gate.allowNextDial('p1');
      gate.markDown('p1');
      expect(downs, ['p1', 'p1']);
    });

    test('waitUntilUp rejects an already-suspended profile', () async {
      gate.suspend('p1');

      await expectLater(
        gate.waitUntilUp('p1'),
        throwsA(isA<SshProfileDownException>()),
      );
    });
  });
}
