import '../../../terminal/fullscreen_cr_ack_config.dart';
import '../../registry/capabilities/terminal_behavior_capability.dart';

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
  FullscreenCrAckStrategy get fullscreenCrAckStrategy =>
      FullscreenCrAckStrategy.composerMovesDown;
  @override
  String? get fullscreenComposerPrefix => '→';
}
