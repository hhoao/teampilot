import 'fullscreen_cr_ack_config.dart';
import 'fullscreen_input_screen_probe.dart';

/// PTY + grid surface used by [FullscreenPtyAutomation] (production: terminal).
abstract interface class FullscreenPtyDeliveryPort {
  bool get isAborted;

  /// Visible viewport height in mirror-grid rows (0 when unknown).
  int get viewportRows;

  FullscreenCrAckConfig get crAckConfig;

  Future<void> syncDisplayGrid();

  /// Completes on the next screen paint, or when [timeout] elapses.
  Future<void> waitForPaint({required Duration timeout});

  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24});

  /// Collapsed-paste chrome ACK when body text is hidden from the grid
  /// (e.g. Claude Code `[Pasted text #N +M lines]`, opencode `[Pasted ~N lines]`).
  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24});

  bool isAtAnchor(FullscreenPromptAnchor anchor);

  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24});

  /// Whether the bottommost composer chrome row is prefix-only (no staged body).
  bool isComposerChromeEmpty({int scanRows = 24});

  /// Whether [needle] is still the body of a composer-prefixed input row.
  bool isNeedleStagedInComposer(String needle, {int scanRows = 24});

  Future<void> clearStagedInput({bool Function()? canExecute});

  Future<void> pasteText(String text, {bool Function()? canExecute});

  Future<void> submitCr({bool Function()? canExecute});

  /// Dismisses a composer popup that would consume the submit CR — e.g.
  /// Claude Code's file-mention autocomplete after pasting "@path" text.
  /// Writes ESC; harmless when no popup is open.
  Future<void> dismissComposerPopup();

  /// Bottom [scanRows] of the mirror grid for ACK-miss diagnostics.
  String describeProbeWindow({int scanRows = 24});
}
