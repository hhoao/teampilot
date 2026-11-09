import 'dart:async';

/// One coalesced ACP transcript patch produced by the desktop runtime.
///
/// [payload] is the app-owned transcript v2 JSONL (delta records, or a compact
/// snapshot when [replace] is true), so the receiver can reuse the transcript
/// codec instead of maintaining a second message codec. Text growth is sent as
/// a full part value, making a patch idempotent if it is applied twice or the
/// receiver already loaded the same state from disk.
final class SessionContentStreamChunk {
  const SessionContentStreamChunk({
    required this.sessionId,
    required this.memberId,
    required this.payload,
    this.replace = false,
  });

  final String sessionId;
  final String memberId;
  final String payload;

  /// True when [payload] is a full snapshot rather than a keyed delta (message
  /// reordering or part removal cannot be expressed incrementally).
  final bool replace;
}

abstract final class SessionContentStreamBus {
  static final StreamController<SessionContentStreamChunk> _controller =
      StreamController<SessionContentStreamChunk>.broadcast();

  static Stream<SessionContentStreamChunk> get stream => _controller.stream;

  static void publish({
    required String sessionId,
    required String memberId,
    required String payload,
    bool replace = false,
  }) {
    final sid = sessionId.trim();
    if (sid.isEmpty || payload.trim().isEmpty || _controller.isClosed) return;
    _controller.add(
      SessionContentStreamChunk(
        sessionId: sid,
        memberId: memberId.trim(),
        payload: payload,
        replace: replace,
      ),
    );
  }
}
