import '../cli/registry/capabilities/terminal_composer_region.dart';

/// Whether [FullscreenPtyAutomation.deliverPasteAndSubmit] may treat a
/// `crStuck` outcome as success and skip clear→paste reinject.
///
/// Only [ComposerSubmitSemantics.regionMovedDown] (Cursor / Codex) leaves
/// submitted text on-screen while painting an empty composer. When that
/// empty chrome is visible **and** the paste needle still appears (transcript
/// residual), the first CR already committed — reinject would duplicate.
bool shouldSkipReinjectAfterCrStuck({
  required ComposerSubmitSemantics semantics,
  required bool composerRegionEmpty,
  required bool needleStillVisible,
}) {
  if (semantics != ComposerSubmitSemantics.regionMovedDown) return false;
  return composerRegionEmpty && needleStillVisible;
}
