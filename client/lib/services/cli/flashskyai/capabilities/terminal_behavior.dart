import '../../../terminal/fullscreen_cr_ack_config.dart';
import '../../registry/capabilities/terminal_behavior_capability.dart';

final class FlashskyaiTerminalBehavior implements TerminalBehaviorCapability {
  const FlashskyaiTerminalBehavior();
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
  FullscreenCrAckStrategy get fullscreenCrAckStrategy =>
      FullscreenCrAckStrategy.anchorCellClears;
  @override
  String? get fullscreenComposerPrefix => '\u276f';
}
