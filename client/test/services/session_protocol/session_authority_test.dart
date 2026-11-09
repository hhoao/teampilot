import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session_protocol/session_authority.dart';
import 'package:teampilot/services/session_protocol/session_control_port.dart';
import 'package:teampilot/services/session_protocol/session_models.dart';

final class _Control implements SessionControlPort {
  int cancels = 0;
  final List<String> refreshes = [];

  @override
  Future<void> cancelTurn({
    required String sessionId,
    required String memberId,
  }) async {
    cancels++;
  }

  @override
  Future<void> refreshWorkspaceSessions(String workspaceId) async {
    refreshes.add(workspaceId);
  }
}

SessionSeatActivity _seat(String state, {String memberId = 'dev'}) =>
    SessionSeatActivity(
      sessionId: 's1',
      memberId: memberId,
      state: state,
      readyToChat: state == SessionSeatActivity.stateIdle,
    );

void main() {
  late _Control control;
  late SessionAuthority authority;

  setUp(() {
    control = _Control();
    authority = SessionAuthority(
      authorityId: 'desk',
      controlPort: control,
      epoch: 7,
    );
  });

  tearDown(() => authority.dispose());

  test('updateSeats emits a delta and snapshots the latest state', () {
    final delta = authority.updateSeats('s1', [
      _seat(SessionSeatActivity.stateWorking),
    ]);

    expect(delta, isNotNull);
    expect(delta!.baseRevision, 0);
    expect(delta.revision, 1);
    expect(authority.snapshot('s1')?.seats.single.state, 'working');
  });

  test('unchanged seats do not emit', () {
    authority.updateSeats('s1', [_seat(SessionSeatActivity.stateWorking)]);

    expect(
      authority.updateSeats('s1', [_seat(SessionSeatActivity.stateWorking)]),
      isNull,
    );
  });

  test('removing a session emits a tombstone delta', () {
    authority.updateSeats('s1', [_seat(SessionSeatActivity.stateWorking)]);

    final delta = authority.removeSession('s1');

    expect(delta, isNotNull);
    expect(delta!.removed, isTrue);
    expect(authority.snapshot('s1'), isNull);
  });

  test('turn.cancel applies to a busy seat', () async {
    authority.updateSeats('s1', [_seat(SessionSeatActivity.stateWorking)]);

    final result = await authority.handleIntent(
      const SessionIntent(
        id: 'i1',
        op: 'turn.cancel',
        sessionId: 's1',
        memberId: 'dev',
        expectedEpoch: 7,
      ),
    );

    expect(result.status, SessionIntentStatus.applied);
    expect(control.cancels, 1);
  });

  test('turn.cancel on an idle seat is a noop', () async {
    authority.updateSeats('s1', [_seat(SessionSeatActivity.stateIdle)]);

    final result = await authority.handleIntent(
      const SessionIntent(
        id: 'i1',
        op: 'turn.cancel',
        sessionId: 's1',
        memberId: 'dev',
      ),
    );

    expect(result.status, SessionIntentStatus.noop);
    expect(result.code, 'turn_already_ended');
    expect(control.cancels, 0);
  });

  test(
    'session.refresh refreshes a workspace without a running session',
    () async {
      final result = await authority.handleIntent(
        const SessionIntent(
          id: 'r1',
          op: 'session.refresh',
          sessionId: '',
          workspaceId: 'ws-1',
          expectedEpoch: 7,
        ),
      );

      expect(result.status, SessionIntentStatus.applied);
      expect(control.refreshes, ['ws-1']);
    },
  );

  test('session.refresh without a workspace is rejected', () async {
    final result = await authority.handleIntent(
      const SessionIntent(id: 'r1', op: 'session.refresh', sessionId: ''),
    );

    expect(result.status, SessionIntentStatus.rejected);
    expect(result.code, 'workspace_required');
    expect(control.refreshes, isEmpty);
  });

  test('stale epoch is rejected', () async {
    authority.updateSeats('s1', [_seat(SessionSeatActivity.stateWorking)]);

    final result = await authority.handleIntent(
      const SessionIntent(
        id: 'i1',
        op: 'turn.cancel',
        sessionId: 's1',
        memberId: 'dev',
        expectedEpoch: 6,
      ),
    );

    expect(result.status, SessionIntentStatus.rejected);
    expect(result.code, 'authority_moved');
  });

  test('expired intent is rejected', () async {
    authority.updateSeats('s1', [_seat(SessionSeatActivity.stateWorking)]);

    final result = await authority.handleIntent(
      SessionIntent(
        id: 'i1',
        op: 'turn.cancel',
        sessionId: 's1',
        memberId: 'dev',
        deadline: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
      ),
    );

    expect(result.status, SessionIntentStatus.expired);
  });

  test('unknown op is rejected', () async {
    authority.updateSeats('s1', [_seat(SessionSeatActivity.stateWorking)]);

    final result = await authority.handleIntent(
      const SessionIntent(id: 'i1', op: 'nope', sessionId: 's1'),
    );

    expect(result.status, SessionIntentStatus.rejected);
    expect(result.code, 'unsupported_op');
  });

  test('content invalidation increments per-session sequence', () {
    final first = authority.publishContentInvalidated(sessionId: 's1');
    final second = authority.publishContentInvalidated(sessionId: 's1');

    expect(first.seq, 1);
    expect(second.seq, 2);
  });
}
