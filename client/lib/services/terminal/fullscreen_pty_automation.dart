import 'fullscreen_cr_ack_config.dart';
import 'fullscreen_input_screen_probe.dart';
import 'fullscreen_pty_delivery_port.dart';
import 'pty_automation_needle.dart';
import 'pty_inject_ack_retry.dart' show PtyInjectAckTiming;
import '../../utils/logging/logger.dart';

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
    pollTimeout: Duration(seconds: 3),
    pollInterval: Duration(milliseconds: 100),
    afterPasteAck: Duration(milliseconds: 800),
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

  /// Extra pause after the paste needle is visible, before CR. Needed when
  /// the TUI paints staged text while still inside bracketed-paste (Codex /
  /// Cursor over SSH); a CR in that window becomes a newline, not submit.
  final Duration afterPasteAck;
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
  Future<FullscreenPtyDeliveryOutcome> deliverPasteAndSubmit({
    required FullscreenPtyDeliveryPort port,
    required String text,
    required Duration pasteSettle,
    bool Function()? isAcked,
    bool dismissMentionPopup = false,
  }) async {
    if (isAcked?.call() ?? false) {
      return FullscreenPtyDeliveryOutcome.submitted;
    }
    if (port.isAborted) return FullscreenPtyDeliveryOutcome.aborted;
    bool canExecute() => !(isAcked?.call() ?? false);
    final needle = PtyAutomationNeedle.forText(text);
    await port.syncDisplayGrid();
    await port.clearStagedInput(canExecute: canExecute);
    await Future<void>.delayed(_timing.afterClear);
    await port.pasteText(text, canExecute: canExecute);
    final anchor = await _pollForNeedle(
      port,
      needle,
      minSettle: pasteSettle + _timing.afterPaste + _extraSettleForLength(text),
      pollTimeout: _pastePollBudget(text),
    );
    if (anchor == null) {
      _logProbeMiss(port, needle, text, outcome: 'pasteNotFound');
      return FullscreenPtyDeliveryOutcome.pasteNotFound;
    }
    await _settleAfterPasteAck(port, pasteSettle);
    if (dismissMentionPopup && text.contains('@')) {
      // Mention autocomplete swallows the submit CR; close it first.
      // Harmless when no popup opened (bare ESC in the composer).
      await port.dismissComposerPopup();
    }
    return _pollCrUntilAnchorClears(
      port,
      anchor,
      isAcked: isAcked,
      canExecute: canExecute,
    );
  }

  /// CR-only pass when [text] is already visible on the grid.
  Future<FullscreenPtyDeliveryOutcome> nudgeCrUntilClear({
    required FullscreenPtyDeliveryPort port,
    required String text,
    bool Function()? isAcked,
  }) async {
    final needle = PtyAutomationNeedle.forText(text);
    if (isAcked?.call() ?? false) {
      return FullscreenPtyDeliveryOutcome.submitted;
    }
    if (port.isAborted) return FullscreenPtyDeliveryOutcome.aborted;
    await port.syncDisplayGrid();
    final scanRows = _probeScanRows(port);
    final anchor = port.locateNeedle(needle, scanRows: scanRows);
    if (anchor == null) {
      _logProbeMiss(port, needle, text, outcome: 'nudge-pasteNotFound');
      return FullscreenPtyDeliveryOutcome.pasteNotFound;
    }
    return _pollCrUntilAnchorClears(port, anchor, isAcked: isAcked);
  }

  /// Complete a prior delivery attempt.
  ///
  /// If the paste is already staged on the grid, only CR (swallowed-submit case).
  /// If the needle is absent — deferred surface, pasteNotFound, or cleared
  /// composer — re-run [deliverPasteAndSubmit]. CR-only forever after a miss
  /// leaves mixed-team mail mute.
  Future<FullscreenPtyDeliveryOutcome> retry({
    required FullscreenPtyDeliveryPort port,
    required String text,
    required Duration pasteSettle,
    bool Function()? isAcked,
  }) async {
    if (isAcked?.call() ?? false) {
      return FullscreenPtyDeliveryOutcome.submitted;
    }
    await port.syncDisplayGrid();
    final needle = PtyAutomationNeedle.forText(text);
    if (_locatePasteAck(port, needle) != null) {
      return nudgeCrUntilClear(port: port, text: text, isAcked: isAcked);
    }
    return deliverPasteAndSubmit(
      port: port,
      text: text,
      pasteSettle: pasteSettle,
      isAcked: isAcked,
    );
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
    return _anchoredCr(port, anchor, fence, isAcked: isAcked);
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
    if (isAcked?.call() ?? false) return FullscreenPtyDeliveryOutcome.submitted;
    if (port.isAborted) return FullscreenPtyDeliveryOutcome.aborted;
    await port.submitCr(canExecute: fence);
    // The submit fence may close while the CR write is in flight (hook
    // confirmation); that is a success, not an abort.
    if (isAcked?.call() ?? false) return FullscreenPtyDeliveryOutcome.submitted;
    if (port.isAborted) return FullscreenPtyDeliveryOutcome.aborted;
    await Future<void>.delayed(_timing.afterCr);
    if (isAcked?.call() ?? false) return FullscreenPtyDeliveryOutcome.submitted;
    final scanRows = _probeScanRows(port);
    final acked = await _pollForCrAck(
      port,
      anchor,
      scanRows: scanRows,
      isAcked: isAcked,
    );
    if (!acked) {
      _logCrStuck(port, anchor);
    }
    return acked
        ? FullscreenPtyDeliveryOutcome.submitted
        : FullscreenPtyDeliveryOutcome.crStuck;
  }

  /// CR-ack miss: the anchor never cleared and no hook confirmation arrived.
  /// Logs the probe window so a future miss (@-mention autocomplete popup
  /// swallowing the CR, trust dialog, splash screen) is diagnosable offline.
  void _logCrStuck(FullscreenPtyDeliveryPort port, FullscreenPromptAnchor anchor) {
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
    final primary = port.locateNeedle(needle, scanRows: scanRows);
    if (primary != null) return primary;
    return port.locateCollapsedPasteNeedle(scanRows: scanRows);
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
}
