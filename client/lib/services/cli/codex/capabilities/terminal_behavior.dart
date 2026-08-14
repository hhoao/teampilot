import '../../registry/capabilities/terminal_behavior_capability.dart';
import '../../registry/capabilities/terminal_composer_region.dart';

final class CodexTerminalBehavior implements TerminalBehaviorCapability {
  const CodexTerminalBehavior();
  @override
  bool get supportsTurnInterrupt => true;
  @override
  TurnInterruptPlan get interruptPlan =>
      const TurnInterruptPlan(steps: ['\x03']);
  @override
  bool get bindTitleAttention => false;
  @override
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
    submitSemantics: ComposerSubmitSemantics.regionMovedDown,
    prefixes: ['\u203a'],
  );
}
