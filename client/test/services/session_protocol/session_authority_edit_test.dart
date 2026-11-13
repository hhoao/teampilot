import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session_protocol/session_authority.dart';
import 'package:teampilot/services/session_protocol/session_control_port.dart';
import 'package:teampilot/services/session_protocol/session_models.dart';

final class _Control implements SessionControlPort {
  final List<(String, String, String)> edits = [];
  final List<String> editCancels = [];
  final List<String> turnCancels = [];

  @override
  Future<void> editTurn({
    required String sessionId,
    required String memberId,
    required String operationId,
    required String userMessageId,
    required String text,
  }) async {
    edits.add((operationId, userMessageId, text));
  }

  @override
  Future<void> cancelEdit({
    required String sessionId,
    required String memberId,
    required String operationId,
  }) async {
    editCancels.add(operationId);
  }

  @override
  Future<void> cancelTurn({
    required String sessionId,
    required String memberId,
  }) async {
    turnCancels.add('$sessionId|$memberId');
  }

  @override
  Future<void> refreshWorkspaceSessions(String workspaceId) async {}

  @override
  Future<void> adoptSession({
    required String workspaceId,
    required Map<String, Object?> entry,
  }) async {}

  @override
  Future<void> removeSession({
    required String workspaceId,
    required String sessionId,
  }) async {}
}

SessionIntent _editIntent({
  String operationId = 'op1',
  String memberId = 'm1',
  String messageId = 'u1',
  String text = 'edited',
  String? expectedTurnId,
}) => SessionIntent(
  id: 'intent-1',
  op: 'turn.edit',
  sessionId: 's1',
  memberId: memberId,
  operationId: operationId,
  userMessageId: messageId,
  text: text,
  expectedTurnId: expectedTurnId,
);

SessionOperation _operation({
  String id = 'op1',
  String phase = SessionOperation.phaseQueued,
  int startedAt = 1,
}) => SessionOperation(
  id: id,
  kind: SessionOperation.kindTurnEdit,
  sessionId: 's1',
  memberId: 'm1',
  messageId: 'u1',
  phase: phase,
  startedAt: startedAt,
  updatedAt: startedAt,
);

void main() {
  late SessionAuthority authority;
  late _Control control;

  setUp(() {
    control = _Control();
    authority = SessionAuthority(authorityId: 'authority-1', controlPort: control);
  });

  tearDown(() => authority.dispose());

  void publishSeat({String memberId = 'm1', String? turnId}) {
    authority.updateSeats('s1', [
      SessionSeatActivity(
        sessionId: 's1',
        memberId: memberId,
        state: SessionSeatActivity.stateIdle,
        turnId: turnId,
      ),
    ]);
  }

  test('turn.edit delegates once and replays idempotently by op id', () async {
    publishSeat();

    final first = await authority.handleIntent(_editIntent());
    expect(first.status, SessionIntentStatus.applied);
    expect(control.edits, [('op1', 'u1', 'edited')]);

    // The authority echoes the operation; a replayed intent must not restore
    // the branch a second time.
    authority.publishOperation(_operation());
    final replay = await authority.handleIntent(_editIntent());
    expect(replay.status, SessionIntentStatus.applied);
    expect(control.edits, hasLength(1));
  });

  test('turn.edit rejects an incomplete payload', () async {
    publishSeat();
    final result = await authority.handleIntent(
      _editIntent(messageId: ''),
    );
    expect(result.status, SessionIntentStatus.rejected);
    expect(result.code, 'turn_edit_payload_invalid');
    expect(control.edits, isEmpty);
  });

  test('turn.edit rejects a seat the authority does not run', () async {
    publishSeat();
    final result = await authority.handleIntent(_editIntent(memberId: 'other'));
    expect(result.status, SessionIntentStatus.rejected);
    expect(result.code, 'seat_not_found');
    expect(control.edits, isEmpty);
  });

  test('turn.edit rejects a turn that moved past the expected one', () async {
    publishSeat(turnId: 'turn-2');
    final result = await authority.handleIntent(
      _editIntent(expectedTurnId: 'turn-1'),
    );
    expect(result.status, SessionIntentStatus.rejected);
    expect(result.code, 'turn_moved');
    expect(control.edits, isEmpty);
  });

  test('turn.edit reports a control failure', () async {
    publishSeat();
    final failing = _FailingControl();
    final failingAuthority = SessionAuthority(
      authorityId: 'authority-2',
      controlPort: failing,
    );
    addTearDown(failingAuthority.dispose);
    failingAuthority.updateSeats('s1', [
      const SessionSeatActivity(
        sessionId: 's1',
        memberId: 'm1',
        state: SessionSeatActivity.stateIdle,
      ),
    ]);

    final result = await failingAuthority.handleIntent(_editIntent());
    expect(result.status, SessionIntentStatus.rejected);
    expect(result.code, 'control_failed');
  });

  test('op.cancel stops a running operation', () async {
    publishSeat();
    authority.publishOperation(_operation(phase: SessionOperation.phaseRestoring));

    final result = await authority.handleIntent(
      const SessionIntent(
        id: 'intent-2',
        op: 'op.cancel',
        sessionId: 's1',
        memberId: 'm1',
        operationId: 'op1',
      ),
    );
    expect(result.status, SessionIntentStatus.applied);
    expect(control.editCancels, ['op1']);
  });

  test('op.cancel on a terminal operation is a noop', () async {
    publishSeat();
    authority.publishOperation(_operation(phase: SessionOperation.phaseConfirmed));

    final result = await authority.handleIntent(
      const SessionIntent(
        id: 'intent-3',
        op: 'op.cancel',
        sessionId: 's1',
        memberId: 'm1',
        operationId: 'op1',
      ),
    );
    expect(result.status, SessionIntentStatus.noop);
    expect(result.code, 'already_terminal');
    expect(control.editCancels, isEmpty);
  });

  test('op.cancel for an unknown operation is a noop', () async {
    publishSeat();
    final result = await authority.handleIntent(
      const SessionIntent(
        id: 'intent-4',
        op: 'op.cancel',
        sessionId: 's1',
        memberId: 'm1',
        operationId: 'missing',
      ),
    );
    expect(result.status, SessionIntentStatus.noop);
    expect(result.code, 'unknown_operation');
  });

  test('published operations ride the snapshot and the delta', () async {
    publishSeat();
    final delta = authority.publishOperation(
      _operation(phase: SessionOperation.phaseDelivering),
    );

    expect(delta, isNotNull);
    expect(delta!.operations.single.phase, SessionOperation.phaseDelivering);
    final snapshot = authority.snapshot('s1');
    expect(snapshot!.operation('op1')?.phase, SessionOperation.phaseDelivering);

    // An unchanged phase must not emit another delta.
    expect(
      authority.publishOperation(
        _operation(phase: SessionOperation.phaseDelivering),
      ),
      isNull,
    );
  });

  test('a seat update keeps the operations in the delta', () async {
    publishSeat();
    authority.publishOperation(_operation());
    final delta = authority.updateSeats('s1', [
      const SessionSeatActivity(
        sessionId: 's1',
        memberId: 'm1',
        state: SessionSeatActivity.stateWorking,
      ),
    ]);
    expect(delta!.operations.single.id, 'op1');
  });
}

final class _FailingControl extends _Control {
  @override
  Future<void> editTurn({
    required String sessionId,
    required String memberId,
    required String operationId,
    required String userMessageId,
    required String text,
  }) async {
    throw StateError('edit exploded');
  }
}
