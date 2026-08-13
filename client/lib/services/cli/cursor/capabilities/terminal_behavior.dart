import '../../registry/capabilities/terminal_behavior_capability.dart';
import '../../registry/capabilities/terminal_composer_region.dart';

final class CursorTerminalBehavior implements TerminalBehaviorCapability {
  const CursorTerminalBehavior();
  @override
  bool get usesFullScreenInput => true;
  @override
  Duration get fullScreenPasteSettleDelay => const Duration(milliseconds: 150);
  // Cursor echoes staged input, then keeps submitted text in transcript while
  // repainting a fresh composer below it; ACK on composer movement, not clear.
  @override
  bool get usesGridPasteAck => true;
  @override
  bool get forwardsColorSchemeReport => false;
  @override
  TerminalPathDropBehavior get pathDropBehavior =>
      TerminalPathDropBehavior.defaultFor(usesFullScreenInput: true);
  @override
  FullscreenComposerRegionSpec get composerRegion => const FullscreenComposerRegionSpec(
    submitSemantics: ComposerSubmitSemantics.regionMovedDown,
    prefixes: ['→'],
  );
}
