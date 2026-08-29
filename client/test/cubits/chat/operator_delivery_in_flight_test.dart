import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/operator_delivery_in_flight.dart';

void main() {
  test('run lights isInFlight until action completes', () async {
    final tracker = OperatorDeliveryInFlight();
    final gate = Completer<void>();
    final done = tracker.run('sess', () => gate.future);
    expect(tracker.isInFlight('sess'), isTrue);
    expect(tracker.isInFlight('other'), isFalse);
    gate.complete();
    await done;
    expect(tracker.isInFlight('sess'), isFalse);
  });

  test('nested run stays in flight until the outer finally', () async {
    final tracker = OperatorDeliveryInFlight();
    final inner = Completer<void>();
    final outerReleased = Completer<void>();
    final done = tracker.run('sess', () async {
      await tracker.run('sess', () => inner.future);
      await outerReleased.future;
    });
    inner.complete();
    await Future<void>.delayed(Duration.zero);
    expect(tracker.isInFlight('sess'), isTrue);
    outerReleased.complete();
    await done;
    expect(tracker.isInFlight('sess'), isFalse);
  });

  test('exception in action still ends in-flight', () async {
    final tracker = OperatorDeliveryInFlight();
    await expectLater(
      tracker.run('sess', () async {
        throw StateError('boom');
      }),
      throwsA(isA<StateError>()),
    );
    expect(tracker.isInFlight('sess'), isFalse);
  });

  test('clear zeros count while run is outstanding; later end is a no-op', () async {
    final tracker = OperatorDeliveryInFlight();
    final gate = Completer<void>();
    final done = tracker.run('sess', () => gate.future);
    tracker.clear('sess');
    expect(tracker.isInFlight('sess'), isFalse);
    gate.complete();
    await done;
    expect(tracker.isInFlight('sess'), isFalse);
  });

  test('stale wrap after clear must not drop a newer send', () async {
    final tracker = OperatorDeliveryInFlight();
    final gateA = Completer<void>();
    final doneA = tracker.run('sess', () => gateA.future);
    tracker.clear('sess');
    final gateB = Completer<void>();
    final doneB = tracker.run('sess', () => gateB.future);
    expect(tracker.isInFlight('sess'), isTrue);
    gateA.complete();
    await doneA;
    expect(
      tracker.isInFlight('sess'),
      isTrue,
      reason: "A's finally must not decrement B's count",
    );
    gateB.complete();
    await doneB;
    expect(tracker.isInFlight('sess'), isFalse);
  });

  test('empty session id is a no-op', () async {
    final tracker = OperatorDeliveryInFlight();
    await tracker.run('  ', () async {});
    expect(tracker.isInFlight('  '), isFalse);
    expect(tracker.isInFlight(''), isFalse);
    tracker.clear('');
  });

  test('onChanged fires on begin and end', () async {
    var n = 0;
    final tracker = OperatorDeliveryInFlight(onChanged: () => n++);
    await tracker.run('sess', () async {});
    expect(n, 2);
  });
}
