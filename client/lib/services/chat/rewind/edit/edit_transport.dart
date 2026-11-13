import 'edit_operation.dart';

/// Runs an edited-message resend somewhere else (today: the desktop authority).
///
/// [submit] must resolve as soon as the operation is accepted, never when it
/// finishes: the session-plane intent that carries it has a short answer
/// budget. Progress arrives through [operations] and is matched by operation
/// id, so a reconnect that replays terminal states still settles the edit.
abstract interface class SeatEditTransport {
  Future<bool> submit({
    required String operationId,
    required String messageId,
    required String text,
  });

  Future<void> cancel(String operationId);

  Stream<EditOperation> get operations;
}
