import 'fullscreen_input_screen_probe.dart';

/// PTY + grid surface used by [FullscreenPtyAutomation] (production: terminal).
abstract interface class FullscreenPtyDeliveryPort {
  bool get isAborted;

  Future<void> syncDisplayGrid();

  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24});

  bool isAtAnchor(FullscreenPromptAnchor anchor);

  Future<void> clearStagedInput();

  Future<void> pasteText(String text);

  Future<void> submitCr();
}
