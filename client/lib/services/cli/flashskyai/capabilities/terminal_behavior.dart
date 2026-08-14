import '../../registry/capabilities/terminal_behavior_capability.dart';
import '../../registry/capabilities/terminal_composer_region.dart';

final class FlashskyaiTerminalBehavior implements TerminalBehaviorCapability {
  const FlashskyaiTerminalBehavior();
  @override
  bool get supportsTurnInterrupt => true;
  @override
  TurnInterruptPlan get interruptPlan =>
      const TurnInterruptPlan(steps: ['\x03']);
  @override
  bool get bindTitleAttention => false;
  @override
  // FlashskyAI uses the same Ink fullscreen composer as Claude Code (`❯`).
  bool get usesFullScreenInput => true;
  @override
  Duration get fullScreenPasteSettleDelay => const Duration(milliseconds: 10);
  @override
  bool get usesGridPasteAck => true;
  @override
  bool get forwardsColorSchemeReport => true;
  @override
  TerminalPathDropBehavior get pathDropBehavior =>
      TerminalPathDropBehavior.defaultFor(usesFullScreenInput: true);
  @override
  FullscreenComposerRegionSpec get composerRegion => const FullscreenComposerRegionSpec(
    submitSemantics: ComposerSubmitSemantics.regionCleared,
    prefixes: ['\u276f'],
  );
}
