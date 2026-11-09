/// Authority-side port for typed control intents.
///
/// Kept narrow so `services/session_protocol/` does not depend on ChatCubit or
/// the ACP runtime.
abstract interface class SessionControlPort {
  Future<void> cancelTurn({
    required String sessionId,
    required String memberId,
  });

  /// Re-reads [workspaceId]'s session list from the shared home plane.
  ///
  /// Used by a mobile client after it creates a conversation: the desktop
  /// authority has no file watcher on the home, so it must be told to refresh.
  Future<void> refreshWorkspaceSessions(String workspaceId);
}
