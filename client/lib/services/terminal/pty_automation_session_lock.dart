/// Per session+member guard against stacked PTY automation ACK loops.
final class PtyAutomationSessionLock {
  final Set<String> _busy = {};

  bool isBusy(String sessionId, String memberId) =>
      _busy.contains(key(sessionId, memberId));

  bool tryAcquire(String sessionId, String memberId) {
    final k = key(sessionId, memberId);
    if (_busy.contains(k)) return false;
    _busy.add(k);
    return true;
  }

  void release(String sessionId, String memberId) =>
      _busy.remove(key(sessionId, memberId));

  static String key(String sessionId, String memberId) => '$sessionId:$memberId';
}
