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
  Future<FullscreenPtyDeliveryOutcome> deliverPasteAndSubmit({
    required FullscreenPtyDeliveryPort port,
    required String text,
    required Duration pasteSettle,
    bool Function()? isAcked,
  }) async {
    if (port.isAborted) return FullscreenPtyDeliveryOutcome.aborted;
    if (isAcked?.call() ?? false) {
      return FullscreenPtyDeliveryOutcome.submitted;
    }
    final needle = PtyAutomationNeedle.forText(text);
    await port.syncDisplayGrid();
    await port.clearStagedInput();
    await Future<void>.delayed(_timing.afterClear);
    await port.pasteText(
      text,
      canExecute: () => !(isAcked?.call() ?? false),
    );
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
    return _pollCrUntilAnchorClears(port, anchor, isAcked: isAcked);
  }

  /// CR-only pass when [text] is already visible on the grid.
  Future<FullscreenPtyDeliveryOutcome> nudgeCrUntilClear({
    required FullscreenPtyDeliveryPort port,
    required String text,
    bool Function()? isAcked,
  }) async {
    final needle = PtyAutomationNeedle.forText(text);
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

  /// A caller-owned retry is CR-only. The terminal layer never re-pastes:
  /// deciding whether a new staged command is safe belongs to delivery state.
  Future<FullscreenPtyDeliveryOutcome> retry({
    required FullscreenPtyDeliveryPort port,
    required String text,
    required Duration pasteSettle,
    bool Function()? isAcked,
  }) async {
    if (isAcked?.call() ?? false) {
      return FullscreenPtyDeliveryOutcome.submitted;
    }
    return nudgeCrUntilClear(port: port, text: text, isAcked: isAcked);
  }

  Future<FullscreenPtyDeliveryOutcome> _pollCrUntilAnchorClears(
    FullscreenPtyDeliveryPort port,
    FullscreenPromptAnchor anchor, {
    bool Function()? isAcked,
  }) async {
    if (port.crAckConfig.strategy == FullscreenCrAckStrategy.timed) {
      await port.submitCr(canExecute: () => !(isAcked?.call() ?? false));
      await Future<void>.delayed(_timing.afterCr);
      return FullscreenPtyDeliveryOutcome.submitted;
    }

    await port.submitCr(canExecute: () => !(isAcked?.call() ?? false));
    if (port.isAborted) return FullscreenPtyDeliveryOutcome.aborted;
    await Future<void>.delayed(_timing.afterCr);
    if (isAcked?.call() ?? false) return FullscreenPtyDeliveryOutcome.submitted;
    final scanRows = _probeScanRows(port);
    await port.syncDisplayGrid();
    return port.isSubmittedAfterCr(anchor, scanRows: scanRows)
        ? FullscreenPtyDeliveryOutcome.submitted
        : FullscreenPtyDeliveryOutcome.crStuck;
  }

  Future<void> _settleAfterPasteAck(
    FullscreenPtyDeliveryPort port,
    Duration pasteSettle,
  ) async {
    if (port.crAckConfig.strategy != FullscreenCrAckStrategy.composerMovesDown) {
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
      if (_timing.pollInterval > Duration.zero) {
        await Future<void>.delayed(_timing.pollInterval);
      }
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
