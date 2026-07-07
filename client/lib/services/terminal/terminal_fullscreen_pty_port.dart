import 'fullscreen_input_screen_probe.dart';
import 'fullscreen_cr_ack_config.dart';
import 'fullscreen_pty_delivery_port.dart';
import 'terminal_session.dart';

/// [FullscreenPtyDeliveryPort] backed by a live [TerminalSession].
final class TerminalFullscreenPtyPort implements FullscreenPtyDeliveryPort {
  TerminalFullscreenPtyPort(
    this._session, {
    required bool Function() aborted,
    FullscreenCrAckConfig crAckConfig = const FullscreenCrAckConfig.productionDefault(),
  }) : _aborted = aborted,
       _crAckConfig = crAckConfig;

  final TerminalSession _session;
  final bool Function() _aborted;
  final FullscreenCrAckConfig _crAckConfig;

  @override
  bool get isAborted => _aborted();

  @override
  int get viewportRows => _session.engine.grid.rows;

  @override
  FullscreenCrAckConfig get crAckConfig => _crAckConfig;

  @override
  Future<void> syncDisplayGrid() => _session.syncDisplayGrid();

  @override
  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) =>
      _session.locateFullscreenPromptNeedle(
        needle,
        scanRows: scanRows,
        composerPrefix: _crAckConfig.composerPrefix,
      );

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      _session.isFullscreenPromptAtAnchor(anchor);

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) =>
      _session.isFullscreenPromptSubmitted(
        anchor,
        strategy: _crAckConfig.strategy,
        composerPrefix: _crAckConfig.composerPrefix,
        scanRows: scanRows,
      );

  @override
  Future<void> clearStagedInput() => _session.clearStagedInput();

  @override
  Future<void> pasteText(String text) => _session.pasteText(text);

  @override
  Future<void> submitCr() => _session.submitPendingCr();

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      _session.describeProbeWindow(scanRows: scanRows);
}
