import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/seat_lease_cubit.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart'
    show agentSeatKey;
import 'package:teampilot/services/agent_status/seat_lease.dart';

SeatLease _lease(String id, [DateTime? at]) => SeatLease(
      kind: SeatLeaseKind.backgroundTask,
      id: id,
      acquiredAt: at ?? DateTime(2026, 1, 1),
    );

void main() {
  group('SeatLeaseCubit', () {
    test('acquire is idempotent per lease id', () {
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      cubit.acquire(sessionId: 's', memberId: 'm', lease: _lease('a'));
      cubit.acquire(sessionId: 's', memberId: 'm', lease: _lease('a'));
      expect(
        cubit.state.seatHasLeases(sessionId: 's', memberId: 'm'),
        isTrue,
      );
      expect(
        cubit.state.leases[agentSeatKey(sessionId: 's', memberId: 'm')],
        containsPair('a', anything),
      );
    });

    test('release removes exactly the named lease', () {
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      cubit.acquire(sessionId: 's', memberId: 'm', lease: _lease('a'));
      cubit.acquire(sessionId: 's', memberId: 'm', lease: _lease('b'));
      cubit.release(sessionId: 's', memberId: 'm', leaseId: 'a');
      expect(
        cubit.state.leases[agentSeatKey(sessionId: 's', memberId: 'm')]?.keys,
        ['b'],
      );
      cubit.release(sessionId: 's', memberId: 'm', leaseId: 'b');
      expect(
        cubit.state.seatHasLeases(sessionId: 's', memberId: 'm'),
        isFalse,
      );
    });

    test('release for an unknown id is a no-op', () {
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      cubit.release(sessionId: 's', memberId: 'm', leaseId: 'ghost');
      expect(cubit.state.leases, isEmpty);
    });

    test('leases are per-seat, not session-wide', () {
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      cubit.acquire(sessionId: 's', memberId: 'm1', lease: _lease('a'));
      expect(
        cubit.state.seatHasLeases(sessionId: 's', memberId: 'm2'),
        isFalse,
      );
      expect(cubit.state.sessionHasLeases('s'), isTrue);
      expect(cubit.state.sessionHasLeases('other'), isFalse);
    });

    test('clearSeat drops one seat; clearSession drops every seat', () {
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      cubit.acquire(sessionId: 's', memberId: 'm1', lease: _lease('a'));
      cubit.acquire(sessionId: 's', memberId: 'm2', lease: _lease('b'));
      cubit.clearSeat(sessionId: 's', memberId: 'm1');
      expect(
        cubit.state.seatHasLeases(sessionId: 's', memberId: 'm1'),
        isFalse,
      );
      expect(
        cubit.state.seatHasLeases(sessionId: 's', memberId: 'm2'),
        isTrue,
      );
      cubit.clearSession('s');
      expect(cubit.state.leases, isEmpty);
    });

    test('pruneStale drops leases past their kind TTL and keeps fresh ones',
        () {
      final clockBase = DateTime(2026, 1, 1, 12);
      var now = clockBase;
      final cubit = SeatLeaseCubit(
        pruneInterval: null,
        clock: () => now,
      );
      addTearDown(cubit.close);
      // Fresh: acquired "now".
      cubit.acquire(sessionId: 's', memberId: 'm', lease: _lease('fresh', now));
      // Stale: backgroundTask TTL is 60 minutes.
      cubit.acquire(
        sessionId: 's',
        memberId: 'm',
        lease: _lease('stale', now.subtract(const Duration(minutes: 61))),
      );
      now = clockBase.add(const Duration(seconds: 1));
      cubit.pruneStale();
      expect(
        cubit.state.leases[agentSeatKey(sessionId: 's', memberId: 'm')]?.keys,
        ['fresh'],
      );
    });

    test('seatLeaseTtl — backgroundTask keeps a 60-minute safety net', () {
      expect(
        seatLeaseTtl(SeatLeaseKind.backgroundTask),
        const Duration(minutes: 60),
      );
    });
  });
}
