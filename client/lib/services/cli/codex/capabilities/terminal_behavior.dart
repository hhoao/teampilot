import '../../../terminal/fullscreen_cr_ack_config.dart';
import '../../../terminal/fullscreen_input_readiness.dart';
import '../../registry/capabilities/terminal_behavior_capability.dart';

final class CodexTerminalBehavior implements TerminalBehaviorCapability {
  const CodexTerminalBehavior();
  @override
  bool get supportsTurnInterrupt => true;
  @override
  TurnInterruptPlan get interruptPlan =>
      const TurnInterruptPlan(steps: ['\x03']);
  @override
  bool get usesFullScreenInput => true;
  @override
  Duration get fullScreenPasteSettleDelay => const Duration(milliseconds: 150);
  @override
  bool get usesGridPasteAck => true;
  @override
  TerminalPathDropBehavior get pathDropBehavior =>
      TerminalPathDropBehavior.defaultFor(usesFullScreenInput: true);
  @override
  FullscreenCrAckStrategy get fullscreenCrAckStrategy =>
      FullscreenCrAckStrategy.composerMovesDown;
  @override
  String? get fullscreenComposerPrefix => '\u203a';
  @override
  bool get mentionAutocompletePopup => false;

  @override
  FullscreenInputReadiness get inputReadiness => const FullscreenInputReadiness(
    readyNeedles: ['default \u00b7', '\u203a'],
    bootGateNeedles: [
      'Press enter',
      'trust',
      'Yes, continue',
      'Sign in with ChatGPT',
    ],
    // Quiet window after chrome AND probe contents stop changing. Resume
    // paints › / default · immediately, then streams history; CR during
    // that replay is swallowed or stacked (double-send / stuck composer).
    readyDwell: Duration(seconds: 1),
  );
  @override
  Duration get startupDeadline => const Duration(seconds: 15);
}
