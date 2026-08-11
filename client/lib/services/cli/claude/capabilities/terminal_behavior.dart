import '../../../terminal/fullscreen_cr_ack_config.dart';
import '../../registry/capabilities/terminal_behavior_capability.dart';

final class ClaudeTerminalBehavior implements TerminalBehaviorCapability {
  const ClaudeTerminalBehavior();
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
  FullscreenCrAckStrategy get fullscreenCrAckStrategy =>
      FullscreenCrAckStrategy.anchorCellClears;
  @override
  String? get fullscreenComposerPrefix => '\u276f';
}
