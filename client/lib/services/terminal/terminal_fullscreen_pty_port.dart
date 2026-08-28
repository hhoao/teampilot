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

  @override
  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) =>
      _probe.locateFullscreenPromptNeedle(
        needle,
        scanRows: scanRows,
        composerPrefix: _crAckConfig.composerPrefix,
      );

  @override
  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      _probe.locateCollapsedPasteNeedle(
        scanRows: scanRows,
        composerPrefix: _crAckConfig.composerPrefix,
      );

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      _probe.isFullscreenPromptAtAnchor(
        anchor,
        composerPrefix: _crAckConfig.composerPrefix,
      );

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) =>
      _probe.isFullscreenPromptSubmitted(
        anchor,
        strategy: _crAckConfig.strategy,
        composerPrefix: _crAckConfig.composerPrefix,
        scanRows: scanRows,
      );

  @override
  bool isComposerChromeEmpty({int scanRows = 24}) {
    final prefix = _crAckConfig.composerPrefix?.trim();
    if (prefix == null || prefix.isEmpty) return false;
    return _probe.isComposerChromeEmpty(
      composerPrefix: prefix,
      scanRows: scanRows,
    );
  }

  @override
  bool isNeedleStagedInComposer(String needle, {int scanRows = 24}) {
    final prefix = _crAckConfig.composerPrefix?.trim();
    if (prefix == null || prefix.isEmpty) return false;
    return _probe.isNeedleStagedInComposer(
      needle,
      composerPrefix: prefix,
      scanRows: scanRows,
    );
  }

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
  String describeProbeWindow({int scanRows = 24}) =>
      _probe.describeProbeWindow(scanRows: scanRows);
}
