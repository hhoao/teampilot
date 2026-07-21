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
    required bool sessionWorking,
    required bool sessionConnecting,
  }) {
    if (!turnInFlight) return SessionHistoryLiveChrome.none;
    if (sessionWorking) return SessionHistoryLiveChrome.running;
    if (sessionConnecting || !memberRunning) {
      return SessionHistoryLiveChrome.starting;
    }
    return SessionHistoryLiveChrome.running;
  }
}
