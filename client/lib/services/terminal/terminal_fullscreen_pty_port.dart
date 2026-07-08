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
    FullscreenCrAckConfig crAckConfig = const FullscreenCrAckConfig.productionDefault(),
  }) : _input = input,
       _probe = probe,
       _aborted = aborted,
       _crAckConfig = crAckConfig;

  final TerminalInputController _input;
  final TerminalScreenProbeController _probe;
  final bool Function() _aborted;
  final FullscreenCrAckConfig _crAckConfig;

  @override
  bool get isAborted => _aborted();

  @override
  int get viewportRows => _probe.viewportRows;

  @override
  FullscreenCrAckConfig get crAckConfig => _crAckConfig;

  @override
  Future<void> syncDisplayGrid() => _probe.syncDisplayGrid();

  @override
  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) =>
      _probe.locateFullscreenPromptNeedle(
        needle,
        scanRows: scanRows,
        composerPrefix: _crAckConfig.composerPrefix,
      );

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      _probe.isFullscreenPromptAtAnchor(anchor);

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) =>
      _probe.isFullscreenPromptSubmitted(
        anchor,
        strategy: _crAckConfig.strategy,
        composerPrefix: _crAckConfig.composerPrefix,
        scanRows: scanRows,
      );

  @override
  Future<void> clearStagedInput() => _input.clearStagedInput();

  @override
  Future<void> pasteText(String text) => _input.pasteText(text);

  @override
  Future<void> submitCr() => _input.submitPendingCr();

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      _probe.describeProbeWindow(scanRows: scanRows);
}
