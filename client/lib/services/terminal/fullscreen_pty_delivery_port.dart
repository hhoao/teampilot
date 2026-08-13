import '../cli/registry/capabilities/terminal_composer_region.dart'
    show FullscreenComposerRegionSpec;
import 'fullscreen_input_screen_probe.dart';

/// PTY + grid surface used by [FullscreenPtyAutomation] (production: terminal).
abstract interface class FullscreenPtyDeliveryPort {
  bool get isAborted;

  /// Hook-channel prompt-submit confirmation (authoritative over grid probes).
  bool get isAcked;

  /// Visible viewport height in mirror-grid rows (0 when unknown).
  int get viewportRows;

  FullscreenComposerRegionSpec get composerRegion;

  Future<void> syncDisplayGrid();

  ComposerRegion? locateComposerRegion({int scanRows = 24});

  bool regionContainsNeedle(ComposerRegion region, String needle);

  bool isComposerRegionEmpty(ComposerRegion region);

  /// Null [region] scans the whole probe window (null-region submit fallback).
  bool needleAppearsOutsideRegion(
    ComposerRegion? region,
    String needle, {
    int scanRows = 24,
  });

  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24});

  /// Collapsed-paste chrome ACK when body text is hidden from the grid
  /// (e.g. Claude Code `[Pasted text #N +M lines]`, opencode `[Pasted ~N lines]`).
  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24});

  bool isAtAnchor(FullscreenPromptAnchor anchor);

  Future<void> clearStagedInput();

  Future<void> pasteText(String text);

  Future<void> submitCr();

  /// Bottom [scanRows] of the mirror grid for ACK-miss diagnostics.
  String describeProbeWindow({int scanRows = 24});
}
