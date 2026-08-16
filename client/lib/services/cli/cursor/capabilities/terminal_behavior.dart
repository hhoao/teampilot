import '../../../agent_status/agent_attention_state.dart';
import '../../../terminal/fullscreen_cr_ack_config.dart';
import '../../registry/capabilities/terminal_behavior_capability.dart';

/// Classifies Cursor PTY OSC titles into permission attention.
///
/// Bare native title `"Cursor Agent"` is a no-op (null) — cursor-agent re-emits
/// it constantly and it carries no permission signal. Titles containing
/// `action required` / `permission` / `waiting` map to [AgentSeatAttention.waiting].
AgentSeatAttention? detectCursorTitleAttention(String title) {
  if (title.isEmpty) return null;
  final trimmed = title.trim();
  if (trimmed.toLowerCase() == 'cursor agent') return null;

  final lower = trimmed.toLowerCase();
  if (lower.contains('action required') ||
      lower.contains('permission') ||
      lower.contains('waiting')) {
    return AgentSeatAttention.waiting;
  }
  return null;
}

/// True when [title] is cursor-agent's bare native OSC title (case-insensitive).
bool isCursorNativeTitle(String title) =>
    title.trim().toLowerCase() == 'cursor agent';

final class CursorTerminalBehavior implements TerminalBehaviorCapability {
  const CursorTerminalBehavior();
  @override
  bool get supportsTurnInterrupt => true;
  @override
  TurnInterruptPlan get interruptPlan =>
      const TurnInterruptPlan(steps: ['\x03']);
  @override
  bool get bindTitleAttention => true;
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
