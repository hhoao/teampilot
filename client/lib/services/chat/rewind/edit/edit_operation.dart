/// Lifecycle of one edited-message resend.
///
/// The phases are ordered; a transition only ever moves forward. The UI reads
/// this instead of keeping its own busy/pending/hold booleans.
enum EditPhase {
  /// Accepted by the coordinator, not started yet.
  queued,

  /// Stopping the seat and restoring the parent checkpoint.
  restoring,

  /// Relaunching and waiting for the seat to accept input.
  relaunching,

  /// Injecting the edited prompt at the seat.
  delivering,

  /// Prompt delivered; waiting for the transcript to publish the new turn.
  awaitingReplay,

  /// The new turn is on screen; nothing left to show.
  confirmed,

  /// The seat was not restored to a usable state, or the send failed.
  failed,

  /// Stopped from the compose Stop button before the prompt was delivered.
  cancelled;

  bool get isTerminal =>
      this == confirmed || this == failed || this == cancelled;

  bool get isActive => !isTerminal;

  /// Keeps the edited text on screen in place of the old message.
  bool get keepsPendingBubble =>
      this == queued ||
      this == restoring ||
      this == relaunching ||
      this == delivering ||
      this == awaitingReplay;

  /// Requires the transcript to stay frozen so the restore's replay does not
  /// paint the parent branch before the new turn arrives. Once the prompt is
  /// delivered the thread must observe the runtime again to land it.
  bool get holdsTranscript =>
      this == queued ||
      this == restoring ||
      this == relaunching ||
      this == delivering;

  /// The author may resend the same text.
  bool get allowsRetry => this == failed || this == cancelled;

  /// The compose Stop button cancels the operation.
  bool get isCancellable => isActive;
}

enum EditFailure { cancelled, deliveryFailed }

/// Thrown by the rewind workflow when the author stopped the operation between
/// phases. The seat has already been restored, so the caller must roll back.
final class SeatEditCancelled implements Exception {
  const SeatEditCancelled();

  @override
  String toString() => 'SeatEditCancelled';
}

/// One edit transaction. Immutable so the coordinator can publish snapshots.
final class EditOperation {
  const EditOperation({
    required this.id,
    required this.sessionId,
    required this.memberId,
    required this.messageId,
    required this.text,
    required this.phase,
    required this.startedAt,
    this.failure,
    this.detail,
  });

  final String id;
  final String sessionId;
  final String memberId;
  final String messageId;
  final String text;
  final EditPhase phase;
  final DateTime startedAt;
  final EditFailure? failure;
  final String? detail;

  EditOperation copyWith({
    EditPhase? phase,
    EditFailure? failure,
    String? detail,
  }) {
    return EditOperation(
      id: id,
      sessionId: sessionId,
      memberId: memberId,
      messageId: messageId,
      text: text,
      phase: phase ?? this.phase,
      startedAt: startedAt,
      failure: failure ?? this.failure,
      detail: detail ?? this.detail,
    );
  }

  @override
  String toString() =>
      'EditOperation($id, $messageId, ${phase.name}'
      '${failure == null ? '' : ', ${failure!.name}'})';
}
