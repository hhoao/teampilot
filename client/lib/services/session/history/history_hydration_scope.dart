/// Captures the seat identity at the start of an asynchronous history load.
///
/// A view may switch sessions or members before that load completes; the old
/// continuation must not hydrate persisted records into the newly bound seat.
class HistoryHydrationScope {
  const HistoryHydrationScope({
    required this.seat,
    required this.sessionId,
    required this.memberId,
  });

  final Object seat;
  final String sessionId;
  final String memberId;

  bool isCurrent({
    required Object? seat,
    required String sessionId,
    required String memberId,
  }) =>
      identical(this.seat, seat) &&
      this.sessionId == sessionId &&
      this.memberId == memberId;
}
