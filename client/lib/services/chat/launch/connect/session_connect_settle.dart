/// Polls until a session connect leaves the in-flight window.
///
/// [connectWorkspaceSession] returns as soon as tab surfacing schedules async
/// shell prep — callers that must act only after the PTY is up (or has failed)
/// should wait here for [isConnecting] to clear.
///
/// Returns `true` when the connect settled (left the in-flight window) and
/// `false` when the wait gave up: the cubit closed, or [timeout] elapsed while
/// the session was still connecting. Callers must not treat a `false` return
/// as "connect finished" — e.g. [retrySessionLaunch] may return while the
/// session is still connecting if settle timed out or the cubit closed.
Future<bool> awaitSessionConnectSettle({
  required bool Function() isConnecting,
  required bool Function() isClosed,
  Duration pollInterval = const Duration(milliseconds: 50),
  Duration timeout = const Duration(seconds: 90),
  Future<void> Function(Duration duration) delay = Future<void>.delayed,
  DateTime Function() clock = DateTime.now,
}) async {
  final started = clock();
  while (isConnecting()) {
    if (isClosed()) return false;
    if (clock().difference(started) >= timeout) return false;
    await delay(pollInterval);
  }
  return true;
}
