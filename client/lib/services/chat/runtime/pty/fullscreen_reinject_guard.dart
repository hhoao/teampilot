import 'fullscreen_cr_ack_config.dart';

/// Whether [FullscreenPtyAutomation.deliverPasteAndSubmit] may treat a
/// `crStuck` outcome as success and skip clear→paste reinject.
///
/// Only [FullscreenCrAckStrategy.composerMovesDown] (Cursor / Codex) leaves
/// submitted text on-screen while painting an empty composer. When that
/// empty chrome is visible **and** the paste needle still appears (transcript
/// residual), the first CR already committed — reinject would duplicate.
bool shouldSkipReinjectAfterCrStuck({
  required FullscreenCrAckStrategy strategy,
  required bool composerChromeEmpty,
  required bool needleStillVisible,
  bool needleStagedInComposer = false,
}) {
  if (strategy != FullscreenCrAckStrategy.composerMovesDown) return false;
  if (needleStagedInComposer) return false;
  return composerChromeEmpty && needleStillVisible;
}
