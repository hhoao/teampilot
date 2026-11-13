enum AcpProxyPromptDisposition { start, joinInFlight }

/// One phone connection and at most one open turn per ACP session.
class AcpProxySessionBook {
  AcpProxySessionBook();

  final Map<String, _Session> _sessions = {};

  /// Closes the previous connection id for [sessionId], if any.
  /// Returns that previous id, or null.
  String? attach({required String sessionId, required String connectionId}) {
    final session = _sessions[sessionId];
    if (session == null) {
      _sessions[sessionId] = _Session()..connectionId = connectionId;
      return null;
    }
    final previous = session.connectionId;
    session.connectionId = connectionId;
    return previous;
  }

  /// Drops [connectionId] only while it is still a session's current id.
  void detach(String connectionId) {
    for (final session in _sessions.values) {
      if (session.connectionId == connectionId) {
        session.connectionId = null;
      }
    }
  }

  String? connectionFor(String sessionId) => _sessions[sessionId]?.connectionId;

  /// `start` forwards [text]. The same text joins the open turn.
  ///
  /// A different text while that turn is open throws [StateError]. The phone
  /// must not start a second turn. After [finishTurn], the same text is
  /// `start` again.
  AcpProxyPromptDisposition onPrompt({
    required String sessionId,
    required String text,
  }) {
    final session = _sessions.putIfAbsent(sessionId, _Session.new);
    if (session.running) {
      if (session.prompt == text) {
        return AcpProxyPromptDisposition.joinInFlight;
      }
      throw StateError(
        'session $sessionId has an open turn; '
        'a different prompt must not start another',
      );
    }
    session.prompt = text;
    session.running = true;
    return AcpProxyPromptDisposition.start;
  }

  void finishTurn(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) return;
    session.running = false;
    session.prompt = null;
  }

  bool turnInProgress(String sessionId) =>
      _sessions[sessionId]?.running ?? false;
}

class _Session {
  String? connectionId;
  String? prompt;
  bool running = false;
}
