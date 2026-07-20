/// How History should sync [awaitingAssistant] against seat working state.
enum HistoryAwaitingWorkingAction {
  /// No change (not awaiting).
  none,

  /// Reset latch when awaiting ends.
  resetLatch,

  /// Seat is working — latch rising edge / already-working.
  latchWorking,

  /// Seat idle after we saw working — clear Running.
  clearAwaiting,

  /// Seat idle and never latched — schedule grace clear (missed rising edge).
  scheduleGraceClear,
}

/// Pure decision for History Running vs sidebar [workingSessionIds].
///
/// Sidebar only uses working. History Running also uses [awaitingAssistant],
/// which must clear when the seat goes idle — including when the seat was
/// already working at submit (no rising edge) or never entered working.
HistoryAwaitingWorkingAction resolveHistoryAwaitingWorkingAction({
  required bool awaitingAssistant,
  required bool sessionWorking,
  required bool sawWorkingWhileAwaiting,
}) {
  if (!awaitingAssistant) {
    return sawWorkingWhileAwaiting
        ? HistoryAwaitingWorkingAction.resetLatch
        : HistoryAwaitingWorkingAction.none;
  }
  if (sessionWorking) return HistoryAwaitingWorkingAction.latchWorking;
  if (sawWorkingWhileAwaiting) {
    return HistoryAwaitingWorkingAction.clearAwaiting;
  }
  return HistoryAwaitingWorkingAction.scheduleGraceClear;
}

/// Grace before clearing awaiting when the seat never enters workingSessionIds
/// (permission-only pause, missed latch). Long enough that submit→working lag
/// does not drop Running chrome.
const historyAwaitingIdleGrace = Duration(seconds: 4);
