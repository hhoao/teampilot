class AskUserAnswerPendingEntry {
  const AskUserAnswerPendingEntry({
    required this.requestId,
    this.answers,
    this.reject = false,
  });

  final String requestId;
  final List<List<String>>? answers;
  final bool reject;
}

final class AskUserAnswerPendingStore {
  final _entries = <String, AskUserAnswerPendingEntry>{};

  void put({
    required String sessionId,
    required String memberId,
    required AskUserAnswerPendingEntry entry,
  }) {
    _entries[_key(sessionId, memberId, entry.requestId)] = entry;
  }

  AskUserAnswerPendingEntry? take({
    required String sessionId,
    required String memberId,
    required String requestId,
  }) {
    return _entries.remove(_key(sessionId, memberId, requestId));
  }

  void clearSeat({
    required String sessionId,
    required String memberId,
  }) {
    final prefix = '${_seatKey(sessionId, memberId)}/';
    _entries.removeWhere((key, _) => key.startsWith(prefix));
  }

  /// Drop all pending answers for [sessionId] (tab close / session restart).
  void clearSession(String sessionId) {
    final prefix = '${sessionId.trim()}/';
    _entries.removeWhere((key, _) => key.startsWith(prefix));
  }

  String _seatKey(String sessionId, String memberId) => '$sessionId/$memberId';

  String _key(String sessionId, String memberId, String requestId) =>
      '${_seatKey(sessionId, memberId)}/$requestId';
}
