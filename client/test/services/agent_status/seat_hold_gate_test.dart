import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/seat_hold_gate.dart';

void main() {
  SeatHoldGate<String> gate() =>
      SeatHoldGate<String>(staleReply: () => 'stale');

  test('wait completes with the reply from complete', () async {
    final g = gate();
    final future = g.wait(sessionId: 's', memberId: 'm');
    expect(g.hasWaiter(sessionId: 's', memberId: 'm'), isTrue);
    expect(g.complete(sessionId: 's', memberId: 'm', reply: 'allow'), isTrue);
    expect(await future, 'allow');
    expect(g.hasWaiter(sessionId: 's', memberId: 'm'), isFalse);
  });

  test('a second wait resolves the first with the stale reply', () async {
    final g = gate();
    final first = g.wait(sessionId: 's', memberId: 'm');
    final second = g.wait(sessionId: 's', memberId: 'm');
    expect(await first, 'stale');
    g.complete(sessionId: 's', memberId: 'm', reply: 'allow');
    expect(await second, 'allow');
  });

  test('releaseHold resolves null (fall-through to native TUI)', () async {
    final g = gate();
    final future = g.wait(sessionId: 's', memberId: 'm');
    expect(g.releaseHold(sessionId: 's', memberId: 'm'), isTrue);
    expect(await future, isNull);
  });

  test('timeout resolves null', () async {
    final g = gate();
    final future = g.wait(
      sessionId: 's',
      memberId: 'm',
      timeout: const Duration(milliseconds: 10),
    );
    expect(await future, isNull);
    expect(g.hasWaiter(sessionId: 's', memberId: 'm'), isFalse);
  });

  test('complete returns false with no waiter', () async {
    final g = gate();
    expect(g.complete(sessionId: 's', memberId: 'm', reply: 'allow'), isFalse);
  });

  test('clearSeat and clearSession resolve held waiters with the stale reply',
      () async {
    final g = gate();
    final a = g.wait(sessionId: 's1', memberId: 'm1');
    final b = g.wait(sessionId: 's2', memberId: 'm2');
    g.clearSeat(sessionId: 's1', memberId: 'm1');
    g.clearSession('s2');
    expect(await a, 'stale');
    expect(await b, 'stale');
  });
}
