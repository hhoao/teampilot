import 'fullscreen_input_screen_probe.dart';
import 'fullscreen_pty_delivery_port.dart';
import 'terminal_session.dart';

/// [FullscreenPtyDeliveryPort] backed by a live [TerminalSession].
final class TerminalFullscreenPtyPort implements FullscreenPtyDeliveryPort {
  TerminalFullscreenPtyPort(
    this._session, {
    required bool Function() aborted,
  }) : _aborted = aborted;

  final TerminalSession _session;
  final bool Function() _aborted;

  @override
  bool get isAborted => _aborted();

  @override
  int get viewportRows => _session.engine.grid.rows;

  @override
  Future<void> syncDisplayGrid() => _session.syncDisplayGrid();

  @override
  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) =>
      _session.locateFullscreenPromptNeedle(needle, scanRows: scanRows);

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      _session.isFullscreenPromptAtAnchor(anchor);

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
