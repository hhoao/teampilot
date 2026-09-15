import '../../../terminal/fullscreen_cr_ack_config.dart';
import '../../../terminal/fullscreen_input_readiness.dart';
import '../../registry/capabilities/terminal_behavior_capability.dart';

final class FlashskyaiTerminalBehavior implements TerminalBehaviorCapability {
  const FlashskyaiTerminalBehavior();
  @override
  bool get supportsTurnInterrupt => true;
  @override
  TurnInterruptPlan get interruptPlan =>
      const TurnInterruptPlan(steps: ['\x03']);
  @override
  // FlashskyAI uses the same Ink fullscreen composer as Claude Code (`❯`).
  bool get usesFullScreenInput => true;
  @override
  Duration get fullScreenPasteSettleDelay => const Duration(milliseconds: 10);
  @override
  bool get usesGridPasteAck => true;
  @override
  bool get usesHookSubmitAck => true;
  @override
  bool get usesPasteBaseline => false;
  @override
  int get pasteZoneBottomPad => 0;


  @override
  TerminalPathDropBehavior get pathDropBehavior =>
      TerminalPathDropBehavior.defaultFor(usesFullScreenInput: true);
  @override
  FullscreenCrAckStrategy get fullscreenCrAckStrategy =>
      FullscreenCrAckStrategy.anchorCellClears;
  @override
  bool get mentionAutocompletePopup => true;

  @override
  FullscreenInputReadiness get inputReadiness =>
      FullscreenInputReadiness.bootFrameOnly;
  @override
  Duration get startupDeadline => const Duration(seconds: 15);
}
