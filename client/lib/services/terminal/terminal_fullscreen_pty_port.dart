import 'dart:async';

import 'fullscreen_cr_ack_config.dart';
import 'fullscreen_input_screen_probe.dart';
import 'fullscreen_pty_delivery_port.dart';
import 'terminal_input_controller.dart';
import 'terminal_screen_probe_controller.dart';

/// [FullscreenPtyDeliveryPort] backed by session input + screen probes.
final class TerminalFullscreenPtyPort implements FullscreenPtyDeliveryPort {
  TerminalFullscreenPtyPort({
    required TerminalInputController input,
    required TerminalScreenProbeController probe,
    required bool Function() aborted,
    FullscreenCrAckConfig crAckConfig =
        const FullscreenCrAckConfig.productionDefault(),
    Stream<void>? painted,
  }) : _input = input,
       _probe = probe,
       _aborted = aborted,
       _crAckConfig = crAckConfig,
       _painted = painted;

  final TerminalInputController _input;
  final TerminalScreenProbeController _probe;
  final bool Function() _aborted;
  final FullscreenCrAckConfig _crAckConfig;
  final Stream<void>? _painted;

  @override
  bool get isAborted => _aborted();

  @override
  int get viewportRows => _probe.viewportRows;

  @override
  int get cursorRow => _probe.cursorRow;

  @override
  FullscreenCrAckConfig get crAckConfig => _crAckConfig;

  @override
  Future<void> syncDisplayGrid() => _probe.syncDisplayGrid();

  @override
  Future<void> waitForPaint({required Duration timeout}) async {
    if (timeout <= Duration.zero) return;
    final painted = _painted;
    if (painted == null) return;
    try {
      await painted.first.timeout(timeout, onTimeout: () {});
    } on StateError {
      // Bus disposed / stream already closed — same as a paint timeout.
    }
  }

  /// Paste-ACK location. Cursor uses the paste-denominator baseline bottom-scan
  /// (its mirror caret sits below its composer box); other CLIs use the cursor
  /// input zone (cursor row + a small window above for multi-line tails), so a
  /// stray character in a status row below the input box (e.g. a single "1"
  /// matching "17%") is never mistaken for the paste.
  @override
  FullscreenPromptAnchor? locatePasteZoneNeedle(
    String needle, {
    int scanRows = 24,
  }) => _crAckConfig.pasteBaseline
      ? _probe.locateFullscreenPromptNeedle(
          needle,
          scanRows: scanRows,
          bottomPad: _crAckConfig.pasteZoneBottomPad,
        )
      : _probe.locateNeedleInCursorZone(needle);

  @override
  FullscreenPromptAnchor? locateCollapsedPasteZoneNeedle({int scanRows = 24}) =>
      _crAckConfig.pasteBaseline
      ? _probe.locateCollapsedPasteNeedle(
          scanRows: scanRows,
          bottomPad: _crAckConfig.pasteZoneBottomPad,
        )
      : _probe.locateCollapsedPasteInCursorZone();

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      _probe.isFullscreenPromptAtAnchor(anchor);

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) =>
      _probe.isFullscreenPromptSubmitted(
        anchor,
        strategy: _crAckConfig.strategy,
        scanRows: scanRows,
      );

  @override
  bool isNeedleStagedInCursorZone(String needle) =>
      _probe.needleStaysInCursorZone(needle);

  @override
  Future<void> clearStagedInput({bool Function()? canExecute}) =>
      _input.clearStagedInput(canExecute: canExecute);

  @override
  Future<void> pasteText(String text, {bool Function()? canExecute}) =>
      _input.pasteText(text, canExecute: canExecute);

  @override
  Future<void> submitCr({bool Function()? canExecute}) =>
      _input.submitPendingCr(canExecute: canExecute);

  @override
  Future<void> dismissComposerPopup() => _input.writeEscape();

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      _probe.describeProbeWindow(scanRows: scanRows);
}
