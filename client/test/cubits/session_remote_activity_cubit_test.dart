import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session_remote_activity_cubit.dart';
import 'package:teampilot/services/session_protocol/session_models.dart';

SessionSnapshot _snapshot({required int revision, required String state}) =>
    SessionSnapshot(
      sessionId: 's1',
      epoch: 7,
      revision: revision,
      seats: [
        SessionSeatActivity(sessionId: 's1', memberId: 'dev', state: state),
      ],
    );

SessionDelta _delta({
  required int base,
  required int revision,
  required String state,
}) => SessionDelta(
  sessionId: 's1',
  epoch: 7,
  baseRevision: base,
  revision: revision,
  seats: [SessionSeatActivity(sessionId: 's1', memberId: 'dev', state: state)],
);

void main() {
  test('snapshot replaces the projection', () {
    final cubit = SessionRemoteActivityCubit();
    cubit.applySnapshots([
      _snapshot(revision: 1, state: SessionSeatActivity.stateWorking),
    ]);

    expect(cubit.state.isBusy('s1'), isTrue);
    expect(cubit.state.isMemberBusy('s1', 'dev'), isTrue);
    expect(cubit.state.busySessionIds, {'s1'});
  });

  test('matching delta advances the projection', () {
    final cubit = SessionRemoteActivityCubit();
    cubit.applySnapshots([
      _snapshot(revision: 1, state: SessionSeatActivity.stateWorking),
    ]);

    cubit.applyDelta(
      _delta(base: 1, revision: 2, state: SessionSeatActivity.stateIdle),
    );

    expect(cubit.state.isBusy('s1'), isFalse);
    expect(cubit.state.session('s1')?.revision, 2);
  });

  test('out-of-order delta is ignored', () {
    final cubit = SessionRemoteActivityCubit();
    cubit.applySnapshots([
      _snapshot(revision: 5, state: SessionSeatActivity.stateWorking),
    ]);

    cubit.applyDelta(
      _delta(base: 2, revision: 3, state: SessionSeatActivity.stateIdle),
    );

    expect(cubit.state.isBusy('s1'), isTrue);
    expect(cubit.state.session('s1')?.revision, 5);
  });

  test('removed delta drops the session', () {
    final cubit = SessionRemoteActivityCubit();
    cubit.applySnapshots([
      _snapshot(revision: 1, state: SessionSeatActivity.stateWorking),
    ]);

    cubit.applyDelta(
      const SessionDelta(
        sessionId: 's1',
        epoch: 7,
        baseRevision: 1,
        revision: 2,
        seats: [],
        removed: true,
      ),
    );

    expect(cubit.state.session('s1'), isNull);
  });

  test('clear empties the projection', () {
    final cubit = SessionRemoteActivityCubit();
    cubit.applySnapshots([
      _snapshot(revision: 1, state: SessionSeatActivity.stateWorking),
    ]);

    cubit.clear();

    expect(cubit.state.sessions, isEmpty);
  });
}
