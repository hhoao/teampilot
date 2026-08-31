/// Polls until a session connect leaves the in-flight window.
///
/// [connectWorkspaceSession] returns as soon as tab surfacing schedules async
/// shell prep — callers that must act only after the PTY is up (or has failed)
/// should wait here for [isConnecting] to clear.
Future<void> awaitSessionConnectSettle({
  required bool Function() isConnecting,
  required bool Function() isClosed,
  Duration pollInterval = const Duration(milliseconds: 50),
  Duration timeout = const Duration(seconds: 90),
  Future<void> Function(Duration duration) delay = Future<void>.delayed,
  DateTime Function() clock = DateTime.now,
}) async {
  final started = clock();
  while (isConnecting()) {
    if (isClosed()) return;
    if (clock().difference(started) >= timeout) return;
    await delay(pollInterval);
  }
}
