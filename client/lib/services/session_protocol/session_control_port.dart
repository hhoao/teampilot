/// Authority-side port for typed control intents.
///
/// Kept narrow so `services/session_protocol/` does not depend on ChatCubit or
/// the ACP runtime.
abstract interface class SessionControlPort {
  Future<void> cancelTurn({
    required String sessionId,
    required String memberId,
  });

  /// Accepts a delegated edited-message resend. Must return once the operation
  /// is queued, not when it finishes: the intent is answered on a short budget.
  Future<void> editTurn({
    required String sessionId,
    required String memberId,
    required String operationId,
    required String userMessageId,
    required String text,
  });

  /// Stops a delegated operation at its next phase boundary.
  Future<void> cancelEdit({
    required String sessionId,
    required String memberId,
    required String operationId,
  });

  /// Re-reads [workspaceId]'s session list from the shared home plane.
  ///
  /// Used by a mobile client after it creates a conversation: the desktop
  /// authority has no file watcher on the home, so it must be told to refresh.
  Future<void> refreshWorkspaceSessions(String workspaceId);

  /// Adopts a session row created on another device.
  ///
  /// [entry] is a `SessionListEntry.toJson()` snapshot; the authority inserts
  /// it into the local session list and broadcasts a `session.list` delta.
  Future<void> adoptSession({
    required String workspaceId,
    required Map<String, Object?> entry,
  });

  /// Removes a session row created on another device.
  Future<void> removeSession({
    required String workspaceId,
    required String sessionId,
  });
}
