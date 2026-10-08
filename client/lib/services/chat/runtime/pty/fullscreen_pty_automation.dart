import 'fullscreen_cr_ack_config.dart';
import 'fullscreen_input_screen_probe.dart';
import 'fullscreen_pty_delivery_port.dart';
import 'fullscreen_pty_submission_machine.dart';
import 'pty_automation_needle.dart';
import 'pty_inject_ack_retry.dart' show PtyInjectAckTiming;
import '../../../../utils/logging/logger.dart';

/// Outcome of a full-screen paste+CR or CR-only automation pass.
enum FullscreenPtyDeliveryOutcome {
  /// Anchor cleared after CR (message submitted).
  submitted,

  /// Paste rounds exhausted without locating the needle on the grid.
  pasteNotFound,

  /// CR rounds exhausted while anchor still visible.
  crStuck,

  /// Shell closed or disconnected mid-flight.
  aborted,
}

/// Injectable timing for unit tests ([PtyAutomationTiming.instant]).
class PtyAutomationTiming {
  const PtyAutomationTiming({
    required this.afterClear,
    required this.afterPaste,
    required this.afterCr,
    required this.afterReinject,
    required this.crMaxAttempts,
    required this.reinjectMaxAttempts,
    required this.nudgeMaxAttempts,
    required this.scanRows,
    this.pollTimeout = const Duration(seconds: 3),
    this.pollInterval = const Duration(milliseconds: 100),
    this.afterPasteAck = Duration.zero,
    this.afterDismissPopup = Duration.zero,
    this.stagingMaxAttempts = 1,
    this.stagingRetryInterval = Duration.zero,
    this.sendAckTimeout = const Duration(seconds: 12),
  });

  factory PtyAutomationTiming.production() => const PtyAutomationTiming(
    afterClear: PtyInjectAckTiming.afterClear,
    afterPaste: PtyInjectAckTiming.afterPaste,
    afterCr: PtyInjectAckTiming.afterCr,
    afterReinject: PtyInjectAckTiming.afterReinject,
    crMaxAttempts: PtyInjectAckTiming.crMaxAttempts,
    reinjectMaxAttempts: PtyInjectAckTiming.reinjectMaxAttempts,
    nudgeMaxAttempts: PtyInjectAckTiming.nudgeMaxAttempts,
    scanRows: 24,
    pollTimeout: Duration(seconds: 8),
    pollInterval: Duration(milliseconds: 100),
    afterPasteAck: Duration(milliseconds: 800),
    afterDismissPopup: Duration(milliseconds: 150),
    // Staging is retried until a booting TUI (MCP / plugin connect repaints)
    // settles and the needle appears; a miss is NOT a terminal failure.
    // 90 attempts × 2s settle ≈ 3 minutes before pasteNotFound.
    stagingMaxAttempts: 90,
    stagingRetryInterval: Duration(seconds: 2),
    sendAckTimeout: Duration(seconds: 12),
  );

  factory PtyAutomationTiming.instant() => const PtyAutomationTiming(
    afterClear: Duration.zero,
    afterPaste: Duration.zero,
    afterCr: Duration.zero,
    afterReinject: Duration.zero,
    crMaxAttempts: 2,
    reinjectMaxAttempts: 1,
    nudgeMaxAttempts: 2,
    scanRows: 24,
    pollTimeout: Duration.zero,
    pollInterval: Duration.zero,
    afterDismissPopup: Duration.zero,
    stagingMaxAttempts: 2,
    stagingRetryInterval: Duration.zero,
    sendAckTimeout: Duration.zero,
  );

  final Duration afterClear;
  final Duration afterPaste;
  final Duration afterCr;
  final Duration afterReinject;
  final int crMaxAttempts;
  final int reinjectMaxAttempts;
  final int nudgeMaxAttempts;
  final int scanRows;
  final Duration pollTimeout;
  final Duration pollInterval;

  /// First paste + retries before [FullscreenPtySubmissionPhase.pasted] locks.
  /// `1` reproduces the single-attempt pre-state-machine behavior.
  final int stagingMaxAttempts;

  /// Quiet gap between staging retries; lets MCP/plugin repaints settle.
  final Duration stagingRetryInterval;

  /// Ceiling for send-phase ack (grid poll + hook) before giving up.
  final Duration sendAckTimeout;

  /// Extra pause after the paste needle is visible, before CR. Needed when
  /// the TUI paints staged text while still inside bracketed-paste (Codex /
  /// Cursor over SSH); a CR in that window becomes a newline, not submit.
  final Duration afterPasteAck;

  /// Pause between the popup-dismiss ESC and the submit CR. The two writes
  /// land back-to-back in the TUI's stdin and coalesce into ESC+CR =
  /// Alt+Enter (insert-newline) instead of two keystrokes — the message
  /// stays staged in the composer and never submits (verified against real
  /// Claude Code 2.1.211: 50ms gap still fails, 100ms+ submits).
  final Duration afterDismissPopup;
}

/// Content-based full-screen PTY delivery: paste → grid ACK → CR → anchor ACK.
class FullscreenPtyAutomation {
  FullscreenPtyAutomation({PtyAutomationTiming? timing})
    : _timing = timing ?? PtyAutomationTiming.production();

  final PtyAutomationTiming _timing;

  /// Tall TUIs (e.g. cursor-agent) pin the input box near the top; a fixed
  /// bottom-only window misses staged text when the viewport is larger.
  int _probeScanRows(FullscreenPtyDeliveryPort port) {
    final rows = port.viewportRows;
    if (rows <= 0) return _timing.scanRows;
    return rows > _timing.scanRows ? rows : _timing.scanRows;
  }

  bool isTextVisible(FullscreenPtyDeliveryPort port, String text) {
    final needle = PtyAutomationNeedle.forText(text);
    return _locatePasteAck(port, needle) != null;
  }

  /// Clear → paste → locate needle → one fenced CR.
  ///
  /// Always pastes on first deliver — never treat a pre-existing needle as
  /// staged input. After `--resume`, the same user text often still sits in
  /// the transcript near the composer; skipping paste then only nudges CR and
  /// the new message never reaches the prompt (retry/nudge may CR-only).
  ///
  /// [isAcked] (optional) is the hook-channel prompt-submit confirmation —
  /// the authoritative "message already submitted" signal. When it flips true
  /// mid-poll (grid probe lagging the real commit), reinject must NOT re-paste:
  /// that is exactly how a single send becomes multiple user rows / bubbles.
  ///
  /// [dismissMentionPopup] (optional): send ESC before the CR when [text]
  /// contains "@". Claude Code's file-mention autocomplete opens on "@path"
  /// pastes and consumes the submit CR (message never committed; verified
  /// against real Claude Code 2.1.211 in a PTY — 2026-09-04).
  ///
  /// The submission runs through [FullscreenPtySubmission]:
  ///  - `staging` retries clear+paste until the needle appears (a booting TUI
  ///    can eat the first paste while MCP/plugin connect repaints overwrite the
  ///    half-painted composer), bounded by [PtyAutomationTiming.stagingMaxAttempts]
  ///    — a miss is NOT a terminal failure yet, but a message is lost if we
  ///    give up here, so the operator never hears success.
  ///  - `pasted` locks the submission: once the needle is on the grid the
  ///    machine never returns to `staging`, so send-phase retries only re-CR
  ///    and can never duplicate a user row.
  Future<FullscreenPtyDeliveryOutcome> deliverPasteAndSubmit({
    required FullscreenPtyDeliveryPort port,
    required String text,
    required Duration pasteSettle,
    bool Function()? isAcked,
    bool dismissMentionPopup = false,
  }) {
    final machine = FullscreenPtySubmission(
      budget: submissionBudget(),
      now: DateTime.now,
    );
    machine.begin();
    return continueSubmission(
      machine,
      port: port,
      text: text,
      pasteSettle: pasteSettle,
      isAcked: isAcked,
      dismissMentionPopup: dismissMentionPopup,
    );
  }

  /// Drives an existing [FullscreenPtySubmission] to a terminal phase.
  ///
  /// One submission = one [FullscreenPtySubmission] instance. Gate retries
  /// (doorbell re-ring) reuse the same instance so the state machine keeps its
  /// invariant across attempts:
  ///  - `staging`  → re-staging (retriable) until the needle appears;
  ///  - `pasted`   → send only (CR), never returns to staging;
  ///  - `awaitingAck` → re-CR / wait for hook, never re-pastes.
  Future<FullscreenPtyDeliveryOutcome> continueSubmission(
    FullscreenPtySubmission machine, {
    required FullscreenPtyDeliveryPort port,
    required String text,
    required Duration pasteSettle,
    bool Function()? isAcked,
    bool dismissMentionPopup = false,
  }) async {
    if (isAcked?.call() ?? false) {
      machine.noteAckedWhileStaging();
      return _machineOutcome(machine, stagingExhausted: true);
    }
    if (port.isAborted) {
      machine.abort();
      return _machineOutcome(machine, stagingExhausted: true);
    }
    return _driveToTerminal(
      machine,
      port: port,
      text: text,
      pasteSettle: pasteSettle,
      isAcked: isAcked,
      dismissMentionPopup: dismissMentionPopup,
    );
  }

  Future<FullscreenPtyDeliveryOutcome> _driveToTerminal(
    FullscreenPtySubmission machine, {
    required FullscreenPtyDeliveryPort port,
    required String text,
    required Duration pasteSettle,
    bool Function()? isAcked,
    bool dismissMentionPopup = false,
  }) async {
    var anchor = _stagedAnchor(port, text);
    var stageMissLogged = false;
    while (!machine.isTerminal) {
      switch (machine.phase) {
        case FullscreenPtySubmissionPhase.staging:
          anchor = await _stagingOnce(
            machine,
            port: port,
            text: text,
            pasteSettle: pasteSettle,
            isAcked: isAcked,
          );
          if (machine.phase == FullscreenPtySubmissionPhase.staging) {
            if (isAcked?.call() ?? false) {
              machine.noteAckedWhileStaging();
              return _machineOutcome(machine, stagingExhausted: true);
            }
            if (port.isAborted) {
              machine.abort();
              return _machineOutcome(machine, stagingExhausted: true);
            }
            if (!stageMissLogged) {
              stageMissLogged = true;
              _logStageMiss(machine, port, text);
            }
            if (machine.canRetryStaging) {
              if (_timing.stagingRetryInterval > Duration.zero) {
                await Future<void>.delayed(_timing.stagingRetryInterval);
              }
              continue;
            }
            machine.noteStagingMiss();
            _logProbeMiss(
              port,
              PtyAutomationNeedle.forText(text),
              text,
              outcome: 'pasteNotFound',
            );
            return _machineOutcome(machine, stagingExhausted: true);
          }
          continue;
        case FullscreenPtySubmissionPhase.pasted:
        case FullscreenPtySubmissionPhase.awaitingAck:
          await _sendOnce(
            machine,
            port: port,
            anchor: anchor!,
            text: text,
            pasteSettle: pasteSettle,
            isAcked: isAcked,
            dismissMentionPopup: dismissMentionPopup,
          );
          continue;
        case FullscreenPtySubmissionPhase.idle ||
            FullscreenPtySubmissionPhase.done ||
            FullscreenPtySubmissionPhase.failed ||
            FullscreenPtySubmissionPhase.aborted:
          return _machineOutcome(machine, stagingExhausted: true);
      }
    }
    return _machineOutcome(machine, stagingExhausted: true);
  }

  /// One clear+paste+probe attempt. Returns the located anchor (or null).
  Future<FullscreenPromptAnchor?> _stagingOnce(
    FullscreenPtySubmission machine, {
    required FullscreenPtyDeliveryPort port,
    required String text,
    required Duration pasteSettle,
    bool Function()? isAcked,
  }) async {
    machine.noteStagingAttempt();
    bool canExecute() => !(isAcked?.call() ?? false);
    await port.syncDisplayGrid();
    // Clear the composer first: a pre-existing staged body on a resumed session
    // must not be mistaken for the new paste.
    await port.clearStagedInput(canExecute: canExecute);
    await Future<void>.delayed(_timing.afterClear);
    final needle = PtyAutomationNeedle.forText(text);
    final preBaseline = await _capturePasteBaseline(port, needle);
    await port.pasteText(text, canExecute: canExecute);
    final anchor = await _pollForNeedle(
      port,
      needle,
      minSettle: pasteSettle + _timing.afterPaste + _extraSettleForLength(text),
      pollTimeout: _pastePollBudget(text),
    );
    if (anchor == null) return null;
    if (preBaseline != null && anchor.row <= preBaseline.row) {
      // The match sits at or above the post-clear baseline → it is the old
      // transcript echo, not the newly staged line. Treat as a miss.
      appLogger.d(
        '[team-bus] pty-probe-ack stale-baseline needle="$needle" '
        'pre=${preBaseline.row} anchor=${anchor.row} — not the new paste; retry',
      );
      return null;
    }
    machine.noteNeedleFound(); // lock — never return to staging
    return anchor;
  }

  /// Send phase of a locked submission: settle, optional popup dismiss, CR.
  ///
  /// Never re-pastes: staging is closed, so retries here only re-CR.
  ///
  /// `_pollCrUntilAnchorClears` owns the full CR retry loop (grid proof
  /// guards against duplicate user rows); the machine just records the
  /// terminal result. A later gate retry (doorbell re-ring) continues a
  /// fresh submission machine — never a stale `failed` one.
  Future<void> _sendOnce(
    FullscreenPtySubmission machine, {
    required FullscreenPtyDeliveryPort port,
    required FullscreenPromptAnchor anchor,
    required String text,
    required Duration pasteSettle,
    bool Function()? isAcked,
    bool dismissMentionPopup = false,
  }) async {
    if (machine.phase == FullscreenPtySubmissionPhase.pasted) {
      await _settleAfterPasteAck(port, pasteSettle);
      if (dismissMentionPopup && text.contains('@')) {
        // Mention autocomplete swallows the submit CR; close it first.
        // Harmless when no popup opened (bare ESC in the composer).
        await port.dismissComposerPopup();
        // Let the TUI parse the ESC as its own keystroke before the CR lands;
        // back-to-back ESC+CR reads as Alt+Enter = newline, not submit.
        await Future<void>.delayed(
          _timing.afterDismissPopup > Duration.zero
              ? _timing.afterDismissPopup
              : const Duration(milliseconds: 150),
        );
      }
      machine.noteCrIssued();
    }
    if (machine.phase != FullscreenPtySubmissionPhase.awaitingAck) return;
    if (isAcked?.call() ?? false) {
      machine.noteSubmitted();
      return;
    }
    if (port.isAborted) {
      machine.abort();
      return;
    }
    final outcome = await _pollCrUntilAnchorClears(
      port,
      anchor,
      isAcked: isAcked,
      canExecute: () => !(isAcked?.call() ?? false),
    );
    switch (outcome) {
      case FullscreenPtyDeliveryOutcome.submitted:
        machine.noteSubmitted();
      case FullscreenPtyDeliveryOutcome.crStuck:
        machine.noteSendExhausted();
      case FullscreenPtyDeliveryOutcome.aborted:
        machine.abort();
      case FullscreenPtyDeliveryOutcome.pasteNotFound:
        machine.abort();
    }
  }

  FullscreenPromptAnchor? _stagedAnchor(
    FullscreenPtyDeliveryPort port,
    String text,
  ) {
    final needle = PtyAutomationNeedle.forText(text);
    return port.locatePasteZoneNeedle(needle, scanRows: _probeScanRows(port));
  }

  Future<FullscreenPtyDeliveryOutcome> _pollCrUntilAnchorClears(
    FullscreenPtyDeliveryPort port,
    FullscreenPromptAnchor anchor, {
    bool Function()? isAcked,
    bool Function()? canExecute,
  }) {
    final fence = canExecute ?? (() => !(isAcked?.call() ?? false));
    if (port.crAckConfig.strategy == FullscreenCrAckStrategy.timed) {
      return _timedCr(port, fence, isAcked: isAcked);
    }
    if (port.crAckConfig.hookSubmitAck) {
      return _hookOnlyCr(port, fence, isAcked: isAcked);
    }
    return _anchoredCr(port, anchor, fence, isAcked: isAcked);
  }

  /// CR submit confirmed **only** by the hook `promptSubmitted` signal.
  ///
  /// Grid submit probing is unreliable on resumed sessions: an identical older
  /// message in the transcript can be mistaken for the staged line and report
  /// submitted while the CLI never received the new prompt. When the CLI emits
  /// a submit hook ([FullscreenCrAckConfig.hookSubmitAck]), the mirror grid is
  /// used purely for the paste ACK and the submit verdict is the hook alone.
  ///
  /// A swallowed CR is nudged (bounded by [PtyAutomationTiming.crMaxAttempts])
  /// exactly like pressing Enter again; the ack wait repeats each try, and only
  /// a hook confirmation (or the [PtyAutomationTiming.sendAckTimeout] budget)
  /// decides the outcome — never the grid.
  Future<FullscreenPtyDeliveryOutcome> _hookOnlyCr(
    FullscreenPtyDeliveryPort port,
    bool Function() fence, {
    bool Function()? isAcked,
  }) async {
    final deadline = DateTime.now().add(_timing.sendAckTimeout);
    for (var attempt = 0; attempt < _timing.crMaxAttempts; attempt++) {
      if (isAcked?.call() ?? false) {
        return FullscreenPtyDeliveryOutcome.submitted;
      }
      if (port.isAborted) return FullscreenPtyDeliveryOutcome.aborted;
      if (attempt > 0) {
        appLogger.d(
          '[team-bus] pty-hook-cr-retry attempt=$attempt '
          'max=${_timing.crMaxAttempts}',
        );
      }
      await port.submitCr(canExecute: fence);
      // The submit fence may close while the CR write is in flight (hook
      // confirmation); that is a success, not an abort.
      if (isAcked?.call() ?? false) {
        return FullscreenPtyDeliveryOutcome.submitted;
      }
      if (port.isAborted) return FullscreenPtyDeliveryOutcome.aborted;
      final acked = await _pollForHookAck(
        port,
        deadline,
        attemptedAt: DateTime.now(),
        isAcked: isAcked,
      );
      if (acked) return FullscreenPtyDeliveryOutcome.submitted;
      if (DateTime.now().isAfter(deadline)) break;
    }
    _logHookCrStuck(port);
    return FullscreenPtyDeliveryOutcome.crStuck;
  }

  /// Pools `isAcked` (the hook confirmation) until [deadline]. Returns true as
  /// soon as confirmed; the grid is never consulted.
  Future<bool> _pollForHookAck(
    FullscreenPtyDeliveryPort port,
    DateTime deadline, {
    required DateTime attemptedAt,
    bool Function()? isAcked,
  }) async {
    final remainingTotal = deadline.difference(attemptedAt);
    if (remainingTotal <= Duration.zero) {
      return isAcked?.call() ?? false;
    }
    final timeout =
        _timing.pollTimeout > Duration.zero &&
            _timing.pollTimeout < remainingTotal
        ? _timing.pollTimeout
        : remainingTotal;
    final pollDeadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(pollDeadline)) {
      if (isAcked?.call() ?? false) return true;
      if (port.isAborted) return false;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      final slice =
          _timing.pollInterval <= Duration.zero ||
              remaining < _timing.pollInterval
          ? remaining
          : _timing.pollInterval;
      await Future.any<void>([
        port.waitForPaint(timeout: slice),
        if (_timing.pollInterval > Duration.zero) Future<void>.delayed(slice),
      ]);
    }
    return isAcked?.call() ?? false;
  }

  void _logHookCrStuck(FullscreenPtyDeliveryPort port) {
    appLogger.w(
      '[team-bus] pty-hook-cr-stuck strategy=${port.crAckConfig.strategy} '
      'scanRows=${_probeScanRows(port)} viewportRows=${port.viewportRows}',
    );
  }

  Future<FullscreenPtyDeliveryOutcome> _timedCr(
    FullscreenPtyDeliveryPort port,
    bool Function() fence, {
    bool Function()? isAcked,
  }) async {
    // isAcked is authoritative: a hook confirmation closes the delivery fence
    // (state leaves submitIssued) which reads as "aborted" through port
    // predicates — a committed prompt must still report submitted.
    if (isAcked?.call() ?? false) return FullscreenPtyDeliveryOutcome.submitted;
    if (port.isAborted) return FullscreenPtyDeliveryOutcome.aborted;
    await port.submitCr(canExecute: fence);
    await Future<void>.delayed(_timing.afterCr);
    return FullscreenPtyDeliveryOutcome.submitted;
  }

  Future<FullscreenPtyDeliveryOutcome> _anchoredCr(
    FullscreenPtyDeliveryPort port,
    FullscreenPromptAnchor anchor,
    bool Function() fence, {
    bool Function()? isAcked,
  }) async {
    for (var attempt = 0; attempt <= _timing.crMaxAttempts; attempt++) {
      if (isAcked?.call() ?? false) {
        return FullscreenPtyDeliveryOutcome.submitted;
      }
      if (port.isAborted) return FullscreenPtyDeliveryOutcome.aborted;
      if (attempt > 0) {
        if (!_crRetrySafeToResend(port, anchor)) {
          // The grid no longer proves the message is un-submitted — re-CR
          // here risks a duplicate user row. Leave the verdict to the
          // cr-ack probe: run one final submitted check (the mirror grid
          // may have repainted since the last poll missed it) and only
          // fall through to crStuck when it stays ambiguous.
          await port.syncDisplayGrid();
          if (isAcked?.call() ?? false) {
            return FullscreenPtyDeliveryOutcome.submitted;
          }
          final scanRows = _probeScanRows(port);
          if (port.isSubmittedAfterCr(anchor, scanRows: scanRows)) {
            return FullscreenPtyDeliveryOutcome.submitted;
          }
          break;
        }
        // TUI startup overlays (codex "Starting MCP servers", trust screens)
        // swallow the CR while the text stays staged in the composer —
        // nudge again like a human pressing Enter.
        appLogger.d(
          '[team-bus] pty-cr-retry attempt=$attempt '
          'max=${_timing.crMaxAttempts} needle="${anchor.needle}"',
        );
      }
      await port.submitCr(canExecute: fence);
      // The submit fence may close while the CR write is in flight (hook
      // confirmation); that is a success, not an abort.
      if (isAcked?.call() ?? false) {
        return FullscreenPtyDeliveryOutcome.submitted;
      }
      if (port.isAborted) return FullscreenPtyDeliveryOutcome.aborted;
      await Future<void>.delayed(_timing.afterCr);
      if (isAcked?.call() ?? false) {
        return FullscreenPtyDeliveryOutcome.submitted;
      }
      final scanRows = _probeScanRows(port);
      final acked = await _pollForCrAck(
        port,
        anchor,
        scanRows: scanRows,
        isAcked: isAcked,
      );
      if (acked) return FullscreenPtyDeliveryOutcome.submitted;
    }
    _logCrStuck(port, anchor);
    return FullscreenPtyDeliveryOutcome.crStuck;
  }

  /// Resend-safety guard for a CR retry: true only when the grid proves the
  /// staged text is still un-submitted input.
  ///
  /// [FullscreenCrAckStrategy.composerMovesDown] (codex / cursor): the needle
  /// must still be the body of a composer-prefixed row — after a real submit
  /// it moves into the transcript and the bottom composer row repaints empty.
  /// [FullscreenCrAckStrategy.anchorCellClears] (claude): the needle must
  /// still sit at the anchor cells — a cleared composer means submitted.
  /// Resend-safety guard for a CR retry: true only when the grid proves the
  /// staged text is still un-submitted input.
  ///
  /// A needle still in the cursor input zone means the message has not been
  /// consumed and a CR retry cannot duplicate it. Covers both
  /// [FullscreenCrAckStrategy.anchorCellClears] and
  /// [FullscreenCrAckStrategy.composerMovesDown] without a per-CLI prefix.
  bool _crRetrySafeToResend(
    FullscreenPtyDeliveryPort port,
    FullscreenPromptAnchor anchor,
  ) {
    switch (port.crAckConfig.strategy) {
      case FullscreenCrAckStrategy.composerMovesDown:
      case FullscreenCrAckStrategy.anchorCellClears:
        return port.isNeedleStagedInCursorZone(anchor.needle);
      case FullscreenCrAckStrategy.timed:
        return false;
    }
  }

  /// CR-ack miss: the anchor never cleared and no hook confirmation arrived.
  /// Logs the probe window so a future miss (@-mention autocomplete popup
  /// swallowing the CR, trust dialog, splash screen) is diagnosable offline.
  void _logCrStuck(
    FullscreenPtyDeliveryPort port,
    FullscreenPromptAnchor anchor,
  ) {
    final scanRows = _probeScanRows(port);
    appLogger.w(
      '[team-bus] pty-cr-stuck anchor=$anchor scanRows=$scanRows '
      'viewportRows=${port.viewportRows} strategy=${port.crAckConfig.strategy}\n'
      '${port.describeProbeWindow(scanRows: scanRows)}',
    );
  }

  /// Grid paint can lag the CR write (real TUI + synthetic test shells). Poll
  /// like paste ACK so a late submit frame is not reported as [crStuck].
  Future<bool> _pollForCrAck(
    FullscreenPtyDeliveryPort port,
    FullscreenPromptAnchor anchor, {
    required int scanRows,
    bool Function()? isAcked,
  }) async {
    final timeout = _timing.pollTimeout;
    if (timeout <= Duration.zero) {
      await port.syncDisplayGrid();
      return port.isSubmittedAfterCr(anchor, scanRows: scanRows);
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (isAcked?.call() ?? false) return true;
      if (port.isAborted) return false;
      await port.syncDisplayGrid();
      if (port.isSubmittedAfterCr(anchor, scanRows: scanRows)) return true;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      final slice =
          _timing.pollInterval <= Duration.zero ||
              remaining < _timing.pollInterval
          ? remaining
          : _timing.pollInterval;
      await Future.any<void>([
        port.waitForPaint(timeout: slice),
        if (_timing.pollInterval > Duration.zero) Future<void>.delayed(slice),
      ]);
    }
    await port.syncDisplayGrid();
    return port.isSubmittedAfterCr(anchor, scanRows: scanRows);
  }

  Future<void> _settleAfterPasteAck(
    FullscreenPtyDeliveryPort port,
    Duration pasteSettle,
  ) async {
    if (port.crAckConfig.strategy !=
        FullscreenCrAckStrategy.composerMovesDown) {
      return;
    }
    final extra = _timing.afterPasteAck > pasteSettle
        ? _timing.afterPasteAck
        : pasteSettle;
    if (extra <= Duration.zero) return;
    await Future<void>.delayed(extra);
  }

  /// Paste-denominator baseline (cursor): text still present after the clear
  /// is an earlier identical transcript echo. Newly pasted text must appear
  /// STRICTLY below that row — a fresh paste lands in the bottom-pinned input
  /// box, and any match at or above the baseline is the old copy, not this
  /// message. Other CLIs use the cursor input zone and need no baseline.
  ///
  /// Drain AFTER clear, then poll until leftover composer text leaves that
  /// row. `syncDisplayGrid` (`drainForTest`) only applies PTY bytes already
  /// in the buffer — Ctrl-U's redraw can arrive after the first snapshot.
  /// Recording baseline on that snapshot (e.g. needle "A" still at the
  /// composer) makes a same-row re-paste look like the old copy forever.
  Future<FullscreenPromptAnchor?> _capturePasteBaseline(
    FullscreenPtyDeliveryPort port,
    String needle,
  ) async {
    if (!port.crAckConfig.pasteBaseline) return null;
    await port.syncDisplayGrid();
    var hit = _locatePasteAck(port, needle);
    final composerRow = port.pasteZoneComposerRow;
    final timeout = _pasteBaselineClearBudget();
    if (hit == null ||
        composerRow < 0 ||
        hit.row != composerRow ||
        timeout <= Duration.zero) {
      return hit;
    }
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (hit == null || hit.row < composerRow) return hit;
      if (port.isAborted || !DateTime.now().isBefore(deadline)) return hit;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) return hit;
      final slice =
          _timing.pollInterval <= Duration.zero ||
              remaining < _timing.pollInterval
          ? remaining
          : _timing.pollInterval;
      await Future.any<void>([
        port.waitForPaint(timeout: slice),
        if (_timing.pollInterval > Duration.zero) Future<void>.delayed(slice),
      ]);
      await port.syncDisplayGrid();
      hit = _locatePasteAck(port, needle);
    }
  }

  /// Cap on waiting for Ctrl-U to leave the composer before recording
  /// baseline. Paste ACK uses the full [PtyAutomationTiming.pollTimeout]
  /// (MCP/plugin repaint); clear-visible is a short PTY round-trip.
  Duration _pasteBaselineClearBudget() {
    final timeout = _timing.pollTimeout;
    if (timeout <= Duration.zero) return Duration.zero;
    const cap = Duration(seconds: 1);
    return timeout < cap ? timeout : cap;
  }

  /// Polls the mirror grid after paste — PTY echo and [syncDisplayGrid] can lag
  /// the painter (see [TerminalScreenProbeController.syncDisplayGrid]).
  ///
  /// When Claude Code collapses a long paste, the body needle is absent and the
  /// composer shows `[Pasted text #N +M lines]` instead — treat that chrome as ACK.
  Future<FullscreenPromptAnchor?> _pollForNeedle(
    FullscreenPtyDeliveryPort port,
    String needle, {
    required Duration minSettle,
    Duration? pollTimeout,
  }) async {
    if (minSettle > Duration.zero) {
      await Future<void>.delayed(minSettle);
    }
    final timeout = pollTimeout ?? _timing.pollTimeout;
    if (timeout <= Duration.zero) {
      await port.syncDisplayGrid();
      return _locatePasteAck(port, needle);
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (port.isAborted) return null;
      await port.syncDisplayGrid();
      final anchor = _locatePasteAck(port, needle);
      if (anchor != null) return anchor;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      final slice =
          _timing.pollInterval <= Duration.zero ||
              remaining < _timing.pollInterval
          ? remaining
          : _timing.pollInterval;
      await Future.any<void>([
        port.waitForPaint(timeout: slice),
        if (_timing.pollInterval > Duration.zero) Future<void>.delayed(slice),
      ]);
    }
    return null;
  }

  /// Ink TUIs need longer to stage multi-kilobyte pastes before the grid ACK.
  Duration _extraSettleForLength(String text) {
    final over = text.length - 2000;
    if (over <= 0) return Duration.zero;
    // ~0.05ms/char beyond 2k, capped at 2s.
    final ms = (over * 0.05).round().clamp(0, 2000);
    return Duration(milliseconds: ms);
  }

  Duration _pastePollBudget(String text) {
    final over = text.length - 2000;
    if (over <= 0) return _timing.pollTimeout;
    // ~0.5ms/char beyond 2k, capped at 15s total extra.
    final extraMs = (over * 0.5).round().clamp(0, 15000);
    return _timing.pollTimeout + Duration(milliseconds: extraMs);
  }

  FullscreenPromptAnchor? _locatePasteAck(
    FullscreenPtyDeliveryPort port,
    String needle,
  ) {
    final scanRows = _probeScanRows(port);
    final primary = port.locatePasteZoneNeedle(needle, scanRows: scanRows);
    if (primary != null) return primary;
    return port.locateCollapsedPasteZoneNeedle(scanRows: scanRows);
  }

  void _logProbeMiss(
    FullscreenPtyDeliveryPort port,
    String needle,
    String text, {
    required String outcome,
  }) {
    final scanRows = _probeScanRows(port);
    appLogger.w(
      '[team-bus] pty-probe-miss outcome=$outcome '
      'needle="$needle" textChars=${text.length} '
      'scanRows=$scanRows viewportRows=${port.viewportRows}\n'
      '${port.describeProbeWindow(scanRows: scanRows)}',
    );
  }

  /// First staging attempt that failed to place the needle: dump the mirror
  /// grid + cursor row so a repro shows exactly why paste ACK missed (e.g. the
  /// staged text sits outside the cursor input zone, or the cursor row is
  /// stale/misplaced). Logged once per submission to avoid 3 minutes of noise.
  void _logStageMiss(
    FullscreenPtySubmission machine,
    FullscreenPtyDeliveryPort port,
    String text,
  ) {
    final scanRows = _probeScanRows(port);
    appLogger.d(
      '[team-bus] pty-stage-miss attempt=${machine.stagingAttempts} '
      'scanRows=$scanRows viewportRows=${port.viewportRows} '
      'cursorRow=${port.cursorRow} textChars=${text.length}\n'
      '${port.describeProbeWindow(scanRows: scanRows)}',
    );
  }

  FullscreenPtySubmissionBudget submissionBudget() =>
      FullscreenPtySubmissionBudget(
        stagingMaxAttempts: _timing.stagingMaxAttempts,
        stagingRetryInterval: _timing.stagingRetryInterval,
        sendMaxCrAttempts: _timing.crMaxAttempts,
        sendAckTimeout: _timing.sendAckTimeout,
      );

  FullscreenPtyDeliveryOutcome _machineOutcome(
    FullscreenPtySubmission machine, {
    bool? stagingExhausted,
  }) => switch (machine.phase) {
    FullscreenPtySubmissionPhase.done => FullscreenPtyDeliveryOutcome.submitted,
    FullscreenPtySubmissionPhase.failed => switch (machine.failedReason) {
      FullscreenPtySubmissionOutcome.crStuck =>
        FullscreenPtyDeliveryOutcome.crStuck,
      _ => FullscreenPtyDeliveryOutcome.pasteNotFound,
    },
    FullscreenPtySubmissionPhase.aborted =>
      FullscreenPtyDeliveryOutcome.aborted,
    _ => throw StateError(
      'submission machine ended non-terminal: ${machine.phase}',
    ),
  };
}
