/// Pending ask-answer map cleared with attention on seat/tab dispose.
abstract interface class AskUserAnswerPendingPort {
  void clearSeat({required String sessionId, required String memberId});

  void clearSession(String sessionId);
}
