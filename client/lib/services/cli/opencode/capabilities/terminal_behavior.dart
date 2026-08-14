import '../../registry/capabilities/terminal_behavior_capability.dart';
import '../../registry/capabilities/terminal_composer_region.dart';

final class OpencodeTerminalBehavior implements TerminalBehaviorCapability {
  const OpencodeTerminalBehavior();
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
    submitSemantics: ComposerSubmitSemantics.regionCleared,
    prefixes: ['\u2503'],
    border: ComposerBorderSpec(
      left: ['\u2503', '\u2502'],
      bottom: ['\u2580', '\u2500'],
      corner: ['\u2579', '\u2570', '\u2514'],
    ),
  );
}
