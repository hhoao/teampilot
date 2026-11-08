/// Authority-side port for typed control intents.
///
/// Kept narrow so `services/session_protocol/` does not depend on ChatCubit or
/// the ACP runtime.
abstract interface class SessionControlPort {
  Future<void> cancelTurn({
    required String sessionId,
    required String memberId,
  });
}
