import '../cli/registry/capabilities/terminal_composer_region.dart';
import 'fullscreen_input_screen_probe.dart';
import 'fullscreen_pty_delivery_port.dart';
import 'fullscreen_reinject_guard.dart';
import 'pty_automation_needle.dart';
import 'pty_inject_ack_retry.dart';
import 'package:logger/logger.dart';
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
    return _locatePasteAck(port, needle) != null;
  }

  /// Clear → paste → locate needle → CR until anchor clears.
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
    final needle = PtyAutomationNeedle.forText(text);
    final maxReinject = _timing.reinjectMaxAttempts;

    for (var reinject = 0; reinject <= maxReinject; reinject++) {
      if (port.isAborted) return FullscreenPtyDeliveryOutcome.aborted;
      if (isAcked?.call() ?? false) {
        // Hook already confirmed the submit — never re-paste.
        return FullscreenPtyDeliveryOutcome.submitted;
      }

      if (reinject > 0) {
        await Future<void>.delayed(_timing.afterReinject);
      }

      await port.syncDisplayGrid();
      final beforeCrRegion = port.locateComposerRegion();
      await port.clearStagedInput();
      await Future<void>.delayed(_timing.afterClear);
      await port.pasteText(text);
      final anchor = await _pollForNeedle(
        port,
        needle,
        minSettle: pasteSettle + _timing.afterPaste + _extraSettleForLength(text),
        pollTimeout: _pastePollBudget(text),
      );

      if (anchor == null) {
        // Region-scoped fallback: staged inside the region also ACKs.
        await port.syncDisplayGrid();
        final regionAck = port.locateComposerRegion();
        if (regionAck != null &&
            port.regionContainsNeedle(regionAck, needle)) {
          // paste confirmed inside region — proceed to CR
        } else {
          if (reinject < maxReinject) continue;
          _logProbeMiss(port, needle, text, outcome: 'pasteNotFound');
          return FullscreenPtyDeliveryOutcome.pasteNotFound;
        }
      }

      final crOutcome = await _pollCrUntilSubmitted(
        port,
        needle,
        isAcked: isAcked,
        beforeCrRegion: beforeCrRegion,
      );
      switch (crOutcome) {
        case FullscreenPtyDeliveryOutcome.submitted:
          return FullscreenPtyDeliveryOutcome.submitted;
        case FullscreenPtyDeliveryOutcome.aborted:
          return FullscreenPtyDeliveryOutcome.aborted;
        case FullscreenPtyDeliveryOutcome.crStuck:
          if (await _shouldSkipReinject(port, needle, text)) {
            return FullscreenPtyDeliveryOutcome.submitted;
          }
          if (reinject < maxReinject) continue;
          return FullscreenPtyDeliveryOutcome.crStuck;
        case FullscreenPtyDeliveryOutcome.pasteNotFound:
          return FullscreenPtyDeliveryOutcome.crStuck;
      }
    }
    return FullscreenPtyDeliveryOutcome.crStuck;
  }

  /// Cursor/Codex: first CR often already committed while grid ACK still fails.
  /// Empty composer + residual needle ⇒ skip clear→paste (avoids duplicate user turns).
  Future<bool> _shouldSkipReinject(
    FullscreenPtyDeliveryPort port,
    String needle,
    String text,
  ) async {
    await port.syncDisplayGrid();
    final scanRows = _probeScanRows(port);
    final region = port.locateComposerRegion(scanRows: scanRows);
    final skip = shouldSkipReinjectAfterCrStuck(
      semantics: port.composerRegion.submitSemantics,
      composerRegionEmpty: region != null &&
          port.isComposerRegionEmpty(region),
      needleStillVisible: port.locateNeedle(needle, scanRows: scanRows) != null,
    );
    if (skip) {
      appLogger.i(
        '[pty] skip-reinject regionMovedDown empty+needle '
        'textChars=${text.length}',
      );
    }
    return skip;
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

      final outcome = await _pollCrUntilSubmitted(
        port,
        needle,
        maxAttempts: 0,
        beforeCrRegion: port.locateComposerRegion(),
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
  /// resume, not staged input. When [isAcked] already confirmed the submit,
  /// skip the paste entirely — the message is committed.
  Future<FullscreenPtyDeliveryOutcome> retry({
    required FullscreenPtyDeliveryPort port,
    required String text,
    required Duration pasteSettle,
    bool Function()? isAcked,
  }) async {
    if (isAcked?.call() ?? false) {
      return FullscreenPtyDeliveryOutcome.submitted;
    }
    return deliverPasteAndSubmit(
      port: port,
      text: text,
      pasteSettle: pasteSettle,
      isAcked: isAcked,
    );
  }

  Future<FullscreenPtyDeliveryOutcome> _pollCrUntilSubmitted(
    FullscreenPtyDeliveryPort port,
    String needle, {
    int? maxAttempts,
    bool Function()? isAcked,
    ComposerRegion? beforeCrRegion,
  }) async {
    final spec = port.composerRegion;
    if (spec.submitSemantics == ComposerSubmitSemantics.timed) {
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
        // Hook-channel ACK is authoritative over the lagging grid probe: once
        // the CLI confirmed the prompt, stop polling (and let callers skip the
        // reinject) instead of burning crStuck attempts on a stale mirror.
        if (isAcked?.call() ?? false) return true;
        await port.syncDisplayGrid();
        return _regionSubmitted(
          port,
          needle,
          scanRows: scanRows,
          beforeCrRegion: beforeCrRegion,
        );
      },
      onRetry: (_) async => port.submitCr(),
    );
    return switch (outcome) {
      PtyAckPollOutcome.acked => FullscreenPtyDeliveryOutcome.submitted,
      PtyAckPollOutcome.aborted => FullscreenPtyDeliveryOutcome.aborted,
      PtyAckPollOutcome.exhausted => FullscreenPtyDeliveryOutcome.crStuck,
    };
  }

  bool _regionSubmitted(
    FullscreenPtyDeliveryPort port,
    String needle, {
    required int scanRows,
    ComposerRegion? beforeCrRegion,
  }) {
    final spec = port.composerRegion;
    final region = port.locateComposerRegion(scanRows: scanRows);
    switch (spec.submitSemantics) {
      case ComposerSubmitSemantics.regionCleared:
        if (region == null) return false;
        return !port.regionContainsNeedle(region, needle);
      case ComposerSubmitSemantics.regionMovedDown:
        return _hasComposerRegionBelow(port, beforeCrRegion, scanRows: scanRows);
      case ComposerSubmitSemantics.timed:
        return true;
    }
  }

  bool _hasComposerRegionBelow(
    FullscreenPtyDeliveryPort port,
    ComposerRegion? previous, {
    required int scanRows,
  }) {
    final current = port.locateComposerRegion(scanRows: scanRows);
    if (current == null) return false;
    if (previous == null) return false;
    return current.topRow > previous.bottomRow;
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
