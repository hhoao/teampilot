import 'fullscreen_cr_ack_config.dart';
import 'fullscreen_input_screen_probe.dart';

/// PTY + grid surface used by [FullscreenPtyAutomation] (production: terminal).
abstract interface class FullscreenPtyDeliveryPort {
  bool get isAborted;

  /// Visible viewport height in mirror-grid rows (0 when unknown).
  int get viewportRows;

  FullscreenCrAckConfig get crAckConfig;

  Future<void> syncDisplayGrid();

  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24});

  bool isAtAnchor(FullscreenPromptAnchor anchor);

  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24});

  Future<void> clearStagedInput();

  Future<void> pasteText(String text);

  Future<void> submitCr();

  /// Bottom [scanRows] of the mirror grid for ACK-miss diagnostics.
  String describeProbeWindow({int scanRows = 24});
}
