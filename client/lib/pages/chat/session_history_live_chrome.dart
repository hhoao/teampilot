/// In-thread tip chrome under History while a turn is in flight.
enum SessionHistoryLiveChrome {
  /// No footer.
  none,

  /// Optimistic bubble is up but the seat PTY is not ready yet (connect /
  /// landing deliver). Label: starting.
  starting,

  /// Seat is up / working; waiting on the assistant turn. Label: running.
  running,
}

/// Whether History tip chrome should treat a turn as in flight.
///
/// After compose Stop, [userStoppedTurn] suppresses residual [sessionBusy]
/// (PTY idleAfter / spinner noise) so "运行中…" clears immediately once
/// [awaitingAssistant] is cleared by the Stop handler.
bool historyTurnInFlight({
  required bool isSubmitting,
  required bool awaitingAssistant,
  required bool sessionBusy,
  required bool userStoppedTurn,
}) {
  if (isSubmitting || awaitingAssistant) return true;
  if (userStoppedTurn) return false;
  return sessionBusy;
}

extension SessionHistoryLiveChromeX on SessionHistoryLiveChrome {
  bool get isActive => this != SessionHistoryLiveChrome.none;

  /// Resolve Chat tip chrome from turn + seat signals.
  ///
  /// Prefer [starting] until connect finishes and the member PTY is up —
  /// Chat suppresses the full-screen session-starting overlay, so this footer
  /// is the only connect feedback after an optimistic bubble.
  static SessionHistoryLiveChrome resolve({
    required bool turnInFlight,
    required bool memberRunning,
    required bool sessionConnecting,
    bool isDelivering = false,
    bool isInTurn = false,
    bool isAttention = false,
  }) {
    if (!turnInFlight) return SessionHistoryLiveChrome.none;
    if (isInTurn || isAttention) return SessionHistoryLiveChrome.running;
    if (isDelivering || sessionConnecting || !memberRunning) {
      return SessionHistoryLiveChrome.starting;
    }
    return SessionHistoryLiveChrome.running;
  }
}
