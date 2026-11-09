import 'dart:async';

/// In-process invalidation signal for app-owned ACP transcripts.
///
/// The desktop ACP runtime writes the transcript on every commit; forwarding
/// the commit through this bus lets (a) the desktop authority publish a
/// session-plane content event and (b) a mobile history-only view re-read the
/// shared transcript immediately instead of waiting for its 2s fallback poll.
final class SessionContentInvalidation {
  const SessionContentInvalidation({
    required this.sessionId,
    this.memberId = '',
  });

  final String sessionId;
  final String memberId;
}

abstract final class SessionContentInvalidationBus {
  static final StreamController<SessionContentInvalidation> _controller =
      StreamController<SessionContentInvalidation>.broadcast();

  static Stream<SessionContentInvalidation> get stream => _controller.stream;

  static void publish({required String sessionId, String memberId = ''}) {
    final trimmed = sessionId.trim();
    if (trimmed.isEmpty || _controller.isClosed) return;
    _controller.add(
      SessionContentInvalidation(sessionId: trimmed, memberId: memberId.trim()),
    );
  }
}
