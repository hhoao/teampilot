import 'fullscreen_cr_ack_config.dart';
import 'fullscreen_input_screen_probe.dart';
import 'fullscreen_pty_delivery_port.dart';
import 'pty_automation_needle.dart';
import 'pty_inject_ack_retry.dart';
import '../../utils/logger.dart';

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
    return port.locateNeedle(needle, scanRows: _probeScanRows(port)) != null;
  }

  /// Clear → paste → locate needle → CR until anchor clears.
  ///
  /// Always pastes on first deliver — never treat a pre-existing needle as
  /// staged input. After `--resume`, the same user text often still sits in
  /// the transcript near the composer; skipping paste then only nudges CR and
  /// the new message never reaches the prompt (retry/nudge may CR-only).
  Future<FullscreenPtyDeliveryOutcome> deliverPasteAndSubmit({
    required FullscreenPtyDeliveryPort port,
    required String text,
    required Duration pasteSettle,
  }) async {
    final needle = PtyAutomationNeedle.forText(text);
    final maxReinject = _timing.reinjectMaxAttempts;

    for (var reinject = 0; reinject <= maxReinject; reinject++) {
      if (port.isAborted) return FullscreenPtyDeliveryOutcome.aborted;

      if (reinject > 0) {
        await Future<void>.delayed(_timing.afterReinject);
      }

      await port.syncDisplayGrid();
      await port.clearStagedInput();
      await Future<void>.delayed(_timing.afterClear);
      await port.pasteText(text);
      final anchor = await _pollForNeedle(
        port,
        needle,
        minSettle: pasteSettle + _timing.afterPaste,
      );

      if (anchor == null) {
        if (reinject < maxReinject) continue;
        _logProbeMiss(port, needle, text, outcome: 'pasteNotFound');
        return FullscreenPtyDeliveryOutcome.pasteNotFound;
      }

      final crOutcome = await _pollCrUntilAnchorClears(port, anchor);
      switch (crOutcome) {
        case FullscreenPtyDeliveryOutcome.submitted:
          return FullscreenPtyDeliveryOutcome.submitted;
        case FullscreenPtyDeliveryOutcome.aborted:
          return FullscreenPtyDeliveryOutcome.aborted;
        case FullscreenPtyDeliveryOutcome.crStuck:
          if (reinject < maxReinject) continue;
          return FullscreenPtyDeliveryOutcome.crStuck;
        case FullscreenPtyDeliveryOutcome.pasteNotFound:
          return FullscreenPtyDeliveryOutcome.crStuck;
      }
    }
    return FullscreenPtyDeliveryOutcome.crStuck;
  }

  /// CR-only pass when [text] is already visible on the grid.
  Future<FullscreenPtyDeliveryOutcome> nudgeCrUntilClear({
    required FullscreenPtyDeliveryPort port,
    required String text,
  }) async {
    final needle = PtyAutomationNeedle.forText(text);
    final maxRounds = _timing.nudgeMaxAttempts;

    for (var round = 0; round <= maxRounds; round++) {
      if (port.isAborted) return FullscreenPtyDeliveryOutcome.aborted;

      await port.syncDisplayGrid();
      final scanRows = _probeScanRows(port);
      final anchor = port.locateNeedle(needle, scanRows: scanRows);
      if (anchor == null) {
        _logProbeMiss(port, needle, text, outcome: 'nudge-pasteNotFound');
        return FullscreenPtyDeliveryOutcome.pasteNotFound;
      }

      final outcome = await _pollCrUntilAnchorClears(
        port,
        anchor,
        maxAttempts: 0,
      );
      switch (outcome) {
        case FullscreenPtyDeliveryOutcome.submitted:
          return FullscreenPtyDeliveryOutcome.submitted;
        case FullscreenPtyDeliveryOutcome.aborted:
          return FullscreenPtyDeliveryOutcome.aborted;
        case FullscreenPtyDeliveryOutcome.crStuck:
        case FullscreenPtyDeliveryOutcome.pasteNotFound:
          if (round < maxRounds) continue;
          return FullscreenPtyDeliveryOutcome.crStuck;
      }
    }
    return FullscreenPtyDeliveryOutcome.crStuck;
  }

  /// Retry always re-pastes; visible text can be transcript history after
  /// resume, not staged input.
  Future<FullscreenPtyDeliveryOutcome> retry({
    required FullscreenPtyDeliveryPort port,
    required String text,
    required Duration pasteSettle,
  }) async {
    return deliverPasteAndSubmit(
      port: port,
      text: text,
      pasteSettle: pasteSettle,
    );
  }

  Future<FullscreenPtyDeliveryOutcome> _pollCrUntilAnchorClears(
    FullscreenPtyDeliveryPort port,
    FullscreenPromptAnchor anchor, {
    int? maxAttempts,
  }) async {
    if (port.crAckConfig.strategy == FullscreenCrAckStrategy.timed) {
      await port.submitCr();
      await Future<void>.delayed(_timing.afterCr);
      return FullscreenPtyDeliveryOutcome.submitted;
    }

    await port.submitCr();
    final scanRows = _probeScanRows(port);
    final outcome = await ptyAckPollRetry(
      settle: _timing.afterCr,
      maxAttempts: maxAttempts ?? _timing.crMaxAttempts,
      aborted: () => port.isAborted,
      isAcked: (_) async {
        await port.syncDisplayGrid();
        return port.isSubmittedAfterCr(anchor, scanRows: scanRows);
      },
      onRetry: (_) async => port.submitCr(),
    );
    return switch (outcome) {
      PtyAckPollOutcome.acked => FullscreenPtyDeliveryOutcome.submitted,
      PtyAckPollOutcome.aborted => FullscreenPtyDeliveryOutcome.aborted,
      PtyAckPollOutcome.exhausted => FullscreenPtyDeliveryOutcome.crStuck,
    };
  }

  /// Polls the mirror grid after paste — PTY echo and [syncDisplayGrid] can lag
  /// the painter (see [TerminalScreenProbeController.syncDisplayGrid]).
  Future<FullscreenPromptAnchor?> _pollForNeedle(
    FullscreenPtyDeliveryPort port,
    String needle, {
    required Duration minSettle,
  }) async {
    if (minSettle > Duration.zero) {
      await Future<void>.delayed(minSettle);
    }
    if (_timing.pollTimeout <= Duration.zero) {
      await port.syncDisplayGrid();
      return port.locateNeedle(needle, scanRows: _probeScanRows(port));
    }
    final deadline = DateTime.now().add(_timing.pollTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (port.isAborted) return null;
      await port.syncDisplayGrid();
      final anchor = port.locateNeedle(
        needle,
        scanRows: _probeScanRows(port),
      );
      if (anchor != null) return anchor;
      if (_timing.pollInterval > Duration.zero) {
        await Future<void>.delayed(_timing.pollInterval);
      }
    }
    return null;
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
