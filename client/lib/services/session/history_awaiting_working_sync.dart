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

  /// Optimistic turn is up but PTY connect is still in flight — keep Starting;
  /// do not start the idle grace (connect often exceeds [historyAwaitingIdleGrace]).
  deferWhileStarting,
}

/// Pure decision for History Running/Starting vs sidebar [workingSessionIds].
///
/// Sidebar only uses working. History tip chrome also uses [awaitingAssistant],
/// which must clear when the seat goes idle — including when the seat was
/// already working at submit (no rising edge) or never entered working.
///
/// While [sessionConnecting] or the member PTY is not up, keep awaiting without
/// scheduling grace so landing/first-continue Starting survives long connects.
HistoryAwaitingWorkingAction resolveHistoryAwaitingWorkingAction({
  required bool awaitingAssistant,
  required bool sessionWorking,
  required bool sawWorkingWhileAwaiting,
  bool sessionConnecting = false,
  bool memberRunning = true,
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
  if (sessionConnecting || !memberRunning) {
    return HistoryAwaitingWorkingAction.deferWhileStarting;
  }
  return HistoryAwaitingWorkingAction.scheduleGraceClear;
}

/// Grace before clearing awaiting when the seat never enters workingSessionIds
/// (permission-only pause, missed latch). Long enough that submit→working lag
/// does not drop Running chrome. Not used while the seat is still starting.
const historyAwaitingIdleGrace = Duration(seconds: 4);

/// Delay before the second force-reload after a turn ends, so a CLI that
/// flushes transcript after PTY quiet is still picked up. Immediate settle
/// already ran; this is the late-write catch. Not used while awaiting.
const historyTurnEndSettleDelay = Duration(milliseconds: 800);
