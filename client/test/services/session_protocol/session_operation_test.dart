import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session_protocol/session_models.dart';

void main() {
  const operation = SessionOperation(
    id: 'op1',
    kind: SessionOperation.kindTurnEdit,
    sessionId: 's1',
    memberId: 'm1',
    messageId: 'u1',
    phase: SessionOperation.phaseDelivering,
    startedAt: 100,
    updatedAt: 120,
    errorCode: 'delivery_failed',
  );

  test('SessionOperation round-trips and keeps terminal detection', () {
    final decoded = SessionOperation.fromJson(operation.toJson());
    expect(decoded, isNotNull);
    expect(decoded!.id, 'op1');
    expect(decoded.phase, SessionOperation.phaseDelivering);
    expect(decoded.isTerminal, isFalse);
    expect(decoded.errorCode, 'delivery_failed');

    expect(
      const SessionOperation(
        id: 'op2',
        kind: SessionOperation.kindTurnEdit,
        sessionId: 's1',
        memberId: 'm1',
        messageId: 'u1',
        phase: SessionOperation.phaseFailed,
      ).isTerminal,
      isTrue,
    );
  });

  test('an unknown phase still decodes (forward compatibility)', () {
    final decoded = SessionOperation.fromJson({
      'id': 'op1',
      'kind': SessionOperation.kindTurnEdit,
      'sessionId': 's1',
      'phase': 'compacting',
    });
    expect(decoded?.phase, 'compacting');
    expect(decoded?.memberId, '');
    expect(decoded?.isTerminal, isFalse);
  });

  test('snapshots and deltas carry operations', () {
    final snapshot = SessionSnapshot(
      sessionId: 's1',
      epoch: 1,
      revision: 2,
      seats: const [],
      operations: const [operation],
    );
    final decodedSnapshot = SessionSnapshot.fromJson(snapshot.toJson());
    expect(decodedSnapshot!.operation('op1')?.phase, 'delivering');

    final delta = SessionDelta(
      sessionId: 's1',
      epoch: 1,
      baseRevision: 1,
      revision: 2,
      seats: const [],
      operations: const [operation],
    );
    final decodedDelta = SessionDelta.fromJson(delta.toJson());
    expect(decodedDelta!.operations.single.id, 'op1');

    // No operations key = unchanged, not "cleared".
    final empty = SessionDelta.fromJson({
      'sessionId': 's1',
      'epoch': 1,
      'baseRevision': 1,
      'revision': 2,
      'seats': const [],
    });
    expect(empty!.operations, isEmpty);
  });

  test('an edit intent carries its operation payload', () {
    const intent = SessionIntent(
      id: 'i1',
      op: 'turn.edit',
      sessionId: 's1',
      memberId: 'm1',
      operationId: 'op1',
      userMessageId: 'u1',
      text: 'edited',
      expectedTurnId: 'turn-1',
    );
    final decoded = SessionIntent.fromJson(intent.toJson());
    expect(decoded!.operationId, 'op1');
    expect(decoded.userMessageId, 'u1');
    expect(decoded.text, 'edited');
    expect(decoded.expectedTurnId, 'turn-1');
  });
}
