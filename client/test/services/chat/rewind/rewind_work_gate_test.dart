import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/rewind/rewind_work_gate.dart';

void main() {
  test('begin is atomic for one git dir', () {
    final gate = RewindWorkGate();
    expect(gate.begin('/seat'), isTrue);
    expect(gate.begin('/seat'), isFalse);
    gate.end('/seat');
    expect(gate.begin('/seat'), isTrue);
  });

  test('waitForSnapshot waits for the registered tail', () async {
    final gate = RewindWorkGate();
    final release = Completer<void>();
    final started = Completer<void>();
    final snapshot = gate.runSnapshot('/seat', () async {
      started.complete();
      await release.future;
    });
    await started.future;

    var waited = false;
    final waiter = gate.waitForSnapshot('/seat').then((_) => waited = true);
    await Future<void>.delayed(Duration.zero);
    expect(waited, isFalse);

    release.complete();
    await snapshot;
    await waiter;
    expect(waited, isTrue);
  });

  test('snapshots chain instead of overlapping', () async {
    final gate = RewindWorkGate();
    final events = <String>[];
    final first = gate.runSnapshot('/seat', () async {
      events.add('first-start');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      events.add('first-end');
    });
    final second = gate.runSnapshot('/seat', () async {
      events.add('second-start');
    });
    await Future.wait([first, second]);
    expect(events, ['first-start', 'first-end', 'second-start']);
  });
}
