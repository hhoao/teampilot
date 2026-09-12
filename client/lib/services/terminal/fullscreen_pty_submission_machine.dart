/// State machine for a single full-screen PTY submission
/// (clear → paste → grid ACK → CR → submit ACK).
///
/// The machine owns the *staging → pasted → awaitingAck* progression and the
/// retry budgets, but performs no I/O. [FullscreenPtyAutomation] drivers do the
/// grid/PTY work and feed observations back through the transition methods.
///
/// Two rules are load-bearing:
///
///  1. **Staging is retriable.** A booting TUI can eat the first paste(s) when
///     MCP/plugin connect repaints overwrite a half-painted composer. Failures
///     inside `staging` only return to `staging` while the budget remains.
///  2. **`pasted` is a one-way latch.** Once the needle is confirmed on the
///     grid, the machine never returns to `staging`; send-phase retries only
///     re-CR (or wait for the hook ack). Re-pasting an already-staged message
///     is exactly how one operator send becomes repeated user rows.
enum FullscreenPtySubmissionPhase {
  /// No submission in progress.
  idle,

  /// Clear + paste + probe needle. Retriable on miss while budget allows.
  staging,

  /// Needle confirmed on the grid. Locked: only [submitCr] / CR retry.
  pasted,

  /// CR issued; waiting for grid anchor clear or hook `isAcked`.
  awaitingAck,

  /// Terminal success: message submitted (grid ack or hook confirmed).
  done,

  /// Terminal failure: budgets exhausted without submission.
  failed,

  /// Terminal: shell died / fenced closed mid-submission.
  aborted,
}

/// Outcome-reported only when the machine reaches a terminal phase.
enum FullscreenPtySubmissionOutcome {
  /// [done] — anchor cleared or hook confirmed the submit.
  submitted,

  /// [failed] with staging budget exhausted and no needle ever seen.
  pasteNotFound,

  /// [failed] with send budget exhausted while text still staged.
  crStuck,

  /// [aborted] — shell disconnected before submission.
  aborted,
}

/// Retry budgets for one submission.
final class FullscreenPtySubmissionBudget {
  const FullscreenPtySubmissionBudget({
    required this.stagingMaxAttempts,
    this.stagingRetryInterval = Duration.zero,
    this.sendMaxCrAttempts = 3,
    this.sendAckTimeout = const Duration(seconds: 12),
  });

  /// First paste + retries. `1` = single attempt (pre-state-machine behavior).
  final int stagingMaxAttempts;

  /// Quiet gap between staging retries so MCP/plugin repaints settle.
  final Duration stagingRetryInterval;

  /// Re-CR attempts inside `awaitingAck` when the anchor has not cleared.
  final int sendMaxCrAttempts;

  /// Ceiling for send-phase ack (grid poll + hook) before giving up.
  final Duration sendAckTimeout;
}

/// A single full-screen PTY submission staged by [FullscreenPtyAutomation].
final class FullscreenPtySubmission {
  FullscreenPtySubmission({
    FullscreenPtySubmissionBudget? budget,
    DateTime Function()? now,
  }) : _budget = budget ?? const FullscreenPtySubmissionBudget(
         stagingMaxAttempts: 90,
         stagingRetryInterval: Duration(seconds: 2),
       ),
       _now = now ?? DateTime.now;

  final FullscreenPtySubmissionBudget _budget;
  final DateTime Function() _now;

  FullscreenPtySubmissionPhase _phase = FullscreenPtySubmissionPhase.idle;
  int _stagingAttempts = 0;
  int _crAttempts = 0;
  DateTime? _awaitingAckSince;

  /// Terminal failure kind: `pasteNotFound` for staging exhaustion,
  /// `crStuck` for send exhaustion. Read by drivers to map `failed` back to
  /// the automation outcome enum without re-deriving which budget ran out.
  FullscreenPtySubmissionOutcome? failedReason;

  FullscreenPtySubmissionPhase get phase => _phase;

  bool get isTerminal =>
      switch (_phase) {
        FullscreenPtySubmissionPhase.done ||
        FullscreenPtySubmissionPhase.failed ||
        FullscreenPtySubmissionPhase.aborted => true,
        _ => false,
      };

  bool get lockedPasted =>
      _phase == FullscreenPtySubmissionPhase.pasted ||
      _phase == FullscreenPtySubmissionPhase.awaitingAck;

  int get stagingAttemptsRemaining =>
      (_budget.stagingMaxAttempts - _stagingAttempts).clamp(0, 1 << 31);

  bool get canRetryStaging => stagingAttemptsRemaining > 0;

  bool get canRetryCr =>
      _phase == FullscreenPtySubmissionPhase.awaitingAck &&
      _crAttempts < _budget.sendMaxCrAttempts;

  /// Begins a submission: enters `staging`.
  void begin() {
    if (_phase != FullscreenPtySubmissionPhase.idle) return;
    _phase = FullscreenPtySubmissionPhase.staging;
    _stagingAttempts = 0;
    _crAttempts = 0;
    _awaitingAckSince = null;
    failedReason = null;
  }

  /// One staging attempt is starting; the attempt counter advances.
  void noteStagingAttempt() => _stagingAttempts++;

  /// A staging attempt did not place the needle: back to `staging` while
  /// budget remains, otherwise `failed`.
  void noteStagingMiss() {
    if (_phase != FullscreenPtySubmissionPhase.staging) return;
    if (canRetryStaging) return; // stay in staging; driver calls noteStagingAttempt
    _phase = FullscreenPtySubmissionPhase.failed;
    failedReason = FullscreenPtySubmissionOutcome.pasteNotFound;
  }

  /// Needle confirmed: **locks** the submission — never returns to `staging`.
  void noteNeedleFound() {
    if (_phase != FullscreenPtySubmissionPhase.staging) return;
    _phase = FullscreenPtySubmissionPhase.pasted;
  }

  /// Submit CR has been issued: enter `awaitingAck` (first time only).
  void noteCrIssued() {
    if (_phase != FullscreenPtySubmissionPhase.pasted) return;
    _phase = FullscreenPtySubmissionPhase.awaitingAck;
    _awaitingAckSince = _now();
  }

  /// A CR retry inside `awaitingAck` consumed one attempt.
  void noteCrRetry() => _crAttempts++;

  /// Anchor cleared or hook confirmed: terminal success.
  void noteSubmitted() {
    if (_phase == FullscreenPtySubmissionPhase.done) return;
    _phase = FullscreenPtySubmissionPhase.done;
  }

  /// Hook confirmed even while staging: nothing more to paste.
  void noteAckedWhileStaging() {
    if (_phase == FullscreenPtySubmissionPhase.staging) {
      _phase = FullscreenPtySubmissionPhase.done;
    }
  }

  /// Budgets exhausted in the send phase: give up without re-pasting.
  void noteSendExhausted() {
    if (_phase == FullscreenPtySubmissionPhase.awaitingAck) {
      _phase = FullscreenPtySubmissionPhase.failed;
      failedReason = FullscreenPtySubmissionOutcome.crStuck;
    }
  }

  /// True once the send-phase ack budget has elapsed.
  bool get awaitingAckExpired {
    if (_awaitingAckSince == null) return false;
    return _now().difference(_awaitingAckSince!) >= _budget.sendAckTimeout;
  }

  /// Shell died or fence closed.
  void abort() {
    if (isTerminal) return;
    _phase = FullscreenPtySubmissionPhase.aborted;
  }
}