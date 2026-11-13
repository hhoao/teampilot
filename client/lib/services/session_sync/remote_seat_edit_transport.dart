import '../../cubits/session_remote_activity_cubit.dart';
import '../session_protocol/session_client.dart';
import '../session_protocol/session_models.dart';
import '../chat/rewind/edit/edit_operation.dart';
import '../chat/rewind/edit/edit_transport.dart';

/// Projects a desktop-owned seat's delegated edit back into the local
/// [EditOperation] model used by the thread UI.
///
/// The authority owns the runtime, so it owns the phases: [submit] only asks it
/// to start, and [operations] replays whatever it publishes (including the
/// final state after a reconnect).
final class RemoteSeatEditTransport implements SeatEditTransport {
  RemoteSeatEditTransport({
    required SessionClientConnection connection,
    required SessionRemoteActivityCubit activity,
    required this.sessionId,
    required this.memberId,
  }) : _connection = connection,
       _activity = activity;

  final SessionClientConnection _connection;
  final SessionRemoteActivityCubit _activity;
  final String sessionId;
  final String memberId;

  @override
  Future<bool> submit({
    required String operationId,
    required String messageId,
    required String text,
  }) async {
    final result = await _connection.editTurn(
      sessionId: sessionId,
      memberId: memberId,
      operationId: operationId,
      userMessageId: messageId,
      text: text,
    );
    return result.ok;
  }

  @override
  Future<void> cancel(String operationId) async {
    await _connection.cancelOperation(
      sessionId: sessionId,
      memberId: memberId,
      operationId: operationId,
    );
  }

  @override
  Stream<EditOperation> get operations => _activity.stream.expand((state) {
    final session = state.session(sessionId);
    if (session == null) return const Iterable<EditOperation>.empty();
    final mapped = <EditOperation>[];
    for (final op in session.operations) {
      if (op.kind != SessionOperation.kindTurnEdit) continue;
      if (op.memberId != memberId) continue;
      final phase = _phaseOf(op.phase);
      if (phase == null) continue;
      mapped.add(
        EditOperation(
          id: op.id,
          sessionId: op.sessionId,
          memberId: op.memberId,
          messageId: op.messageId,
          // The authority does not echo the text back; the local optimistic
          // copy already carries it and is only used for the bubble.
          text: '',
          phase: phase,
          startedAt: DateTime.fromMillisecondsSinceEpoch(op.startedAt),
          failure: _failureOf(op.phase),
          detail: op.errorCode.isEmpty ? null : op.errorCode,
        ),
      );
    }
    return mapped;
  });

  static EditPhase? _phaseOf(String phase) => switch (phase) {
    SessionOperation.phaseQueued => EditPhase.queued,
    SessionOperation.phaseRestoring => EditPhase.restoring,
    SessionOperation.phaseRelaunching => EditPhase.relaunching,
    SessionOperation.phaseDelivering => EditPhase.delivering,
    SessionOperation.phaseAwaitingReplay => EditPhase.awaitingReplay,
    SessionOperation.phaseConfirmed => EditPhase.confirmed,
    SessionOperation.phaseFailed => EditPhase.failed,
    SessionOperation.phaseCancelled => EditPhase.cancelled,
    _ => null,
  };

  static EditFailure? _failureOf(String phase) => switch (phase) {
    SessionOperation.phaseCancelled => EditFailure.cancelled,
    SessionOperation.phaseFailed => EditFailure.deliveryFailed,
    _ => null,
  };
}
