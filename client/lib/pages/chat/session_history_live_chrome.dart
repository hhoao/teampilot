/// In-thread tip chrome under History while a turn is in flight.
enum SessionHistoryLiveChrome {
  /// No footer.
  none,

  /// Optimistic bubble is up but the seat PTY is not ready yet (connect /
  /// landing deliver). Label: starting.
  starting,

  /// Seat is up / working; waiting on the assistant turn. Label: running.
  running,

  /// No turn in flight, but the seat still holds keep-alive leases — a
  /// background shell task / background subagent outlived the turn.
  /// Label: background work running.
  background,
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
  ///
  /// When no turn is in flight, [sessionHasLeases] promotes the footer to
  /// [background]: the seat's CLI is still working on something that outlived
  /// the turn (background shell task / background subagent).
  static SessionHistoryLiveChrome resolve({
    required bool turnInFlight,
    required bool memberRunning,
    required bool sessionConnecting,
    bool isDelivering = false,
    bool isInTurn = false,
    bool isAttention = false,
    bool sessionHasLeases = false,
  }) {
    if (!turnInFlight) {
      return sessionHasLeases
          ? SessionHistoryLiveChrome.background
          : SessionHistoryLiveChrome.none;
    }
    if (isInTurn || isAttention) return SessionHistoryLiveChrome.running;
    if (isDelivering || sessionConnecting || !memberRunning) {
      return SessionHistoryLiveChrome.starting;
    }
    return SessionHistoryLiveChrome.running;
  }
}
