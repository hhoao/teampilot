import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/session_launch_host.dart';
import 'package:teampilot/cubits/seat_lease_cubit.dart';
import 'package:teampilot/services/agent_status/seat_lease.dart';

/// Minimal host: every interface member we do not care about forwards to
/// noSuchMethod (returns null / throws only if actually touched).
class _FakeHost implements SessionLaunchHost {
  _FakeHost(this.seatLeaseCubit);

  @override
  final SeatLeaseCubit? seatLeaseCubit;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('clearAgentStatusSeat drops the seat lease with attention', () {
    final cubit = SeatLeaseCubit(pruneInterval: null);
    addTearDown(cubit.close);
    cubit.acquire(
      sessionId: 's',
      memberId: 'm',
      lease: SeatLease(
        kind: SeatLeaseKind.backgroundTask,
        id: 'call_1',
        acquiredAt: DateTime(2026, 1, 1),
      ),
    );
    final host = _FakeHost(cubit);

    host.clearAgentStatusSeat(sessionId: 's', memberId: 'm');

    expect(cubit.state.leases, isEmpty);
  });

  test('clearAgentStatusSession drops every seat lease in the session', () {
    final cubit = SeatLeaseCubit(pruneInterval: null);
    addTearDown(cubit.close);
    cubit.acquire(
      sessionId: 's',
      memberId: 'm1',
      lease: SeatLease(
        kind: SeatLeaseKind.backgroundTask,
        id: 'a',
        acquiredAt: DateTime(2026, 1, 1),
      ),
    );
    cubit.acquire(
      sessionId: 's',
      memberId: 'm2',
      lease: SeatLease(
        kind: SeatLeaseKind.backgroundTask,
        id: 'b',
        acquiredAt: DateTime(2026, 1, 1),
      ),
    );
    final host = _FakeHost(cubit);

    host.clearAgentStatusSession('s');

    expect(cubit.state.leases, isEmpty);
  });
}
