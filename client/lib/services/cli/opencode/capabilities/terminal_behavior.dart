import '../../../chat/runtime/pty/fullscreen_cr_ack_config.dart';
import '../../../chat/runtime/pty/fullscreen_input_readiness.dart';
import '../../registry/capabilities/terminal_behavior_capability.dart';

final class OpencodeTerminalBehavior implements TerminalBehaviorCapability {
  const OpencodeTerminalBehavior();
  @override
  bool get supportsTurnInterrupt => true;
  @override
  TurnInterruptPlan get interruptPlan =>
      const TurnInterruptPlan(steps: ['\x03']);
  @override
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
  bool get mentionAutocompletePopup => false;

  @override
  FullscreenInputReadiness get inputReadiness => const FullscreenInputReadiness(
    readyNeedles: ['\u2503'],
    // Boot is async: the landing/composer surface paints before MCP servers
    // and plugins finish connecting, and their connect-repaints overwrite the
    // stub composer. An early paste+CR is eaten and the grid never ACKs it
    // (pasteNotFound on 24-row viewports, race documented in
    // opencode_deliver_integration_test.dart:137). Require the probe window to
    // stay unchanged for the dwell so MCP/plugin repaints keep the gate shut
    // until the TUI is actually idling at a live composer.
    readyDwell: Duration(seconds: 1),
  );
  @override
  Duration get startupDeadline => const Duration(seconds: 15);
}
