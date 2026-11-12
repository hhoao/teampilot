import '../../../../models/hook_entry.dart';
import '../../../agent_runtime/runtime_event.dart';
import '../../../agent_status/agent_status_event.dart';
import '../../registry/capabilities/chat_interaction_capability.dart';
import '../../registry/capabilities/runtime_event_capability.dart';
import '../../registry/capabilities/team_behavior_capability.dart';
import '../../registry/capabilities/terminal_behavior_capability.dart';
import '../../../chat/runtime/pty/fullscreen_cr_ack_config.dart';
import '../../../chat/runtime/pty/fullscreen_input_readiness.dart';

/// Grok has no native TeamPilot roster / member-agent-preset surface.
final class GrokTeamBehavior implements TeamBehaviorCapability {
  const GrokTeamBehavior();

  @override
  bool get supportsNativeTeam => false;

  @override
  bool get longBlockingWaitForMessage => false;

  @override
  bool get supportsLocalStdioBridge => false;

  @override
  Set<String> get doneEventNames => const {};

  @override
  bool get requiresPtyFallback => false;

  @override
  bool get usesDoorbellPush => false;

  @override
  bool get defaultForceWaitBeforeStop => false;

  @override
  bool get usesClaudeRoster => false;

  @override
  bool get usesShellActivity => false;

  @override
  MemberAgentPresetStyle? get agentPresetStyle => null;
}

/// Grok ACP reports structured events; heredoc-normalized hooks are unused.
final class GrokChatInteraction
    implements ChatInteractionCapability, RuntimeEventCapability {
  const GrokChatInteraction();

  @override
  AgentStatusEvent? normalize(Map<String, Object?> body) => null;

  @override
  RuntimeEventEnvelopeDraft? normalizeRuntimeEvent(
    Map<String, Object?> raw,
    RuntimeSeatKey seat,
    DateTime occurredAt,
  ) => null;

  @override
  RuntimeCorrelationStrength get promptCorrelationStrength =>
      RuntimeCorrelationStrength.exact;

  @override
  List<HookEntry> managedHookEntries(RuntimeEventHookContext context) =>
      const [];

  @override
  bool get supportsStructuredAsk => false;

  @override
  bool get supportsInChatAnswer => false;

  @override
  bool get supportsMultiSelectInChat => false;

  @override
  bool get supportsMultiQuestionInChat => false;

  @override
  bool get supportsInChatPermissionReply => false;

  @override
  AskUserAnswerKind get answerKind => AskUserAnswerKind.none;

  @override
  bool get supportsInChatApproval => false;

  @override
  ExitPlanApprovalKind get approvalKind => ExitPlanApprovalKind.none;
}

/// Grok is ACP-only, so this behavior is only consulted by shared defaults.
/// Keep the conservative full-screen profile used by the Gemini family.
final class GrokTerminalBehavior implements TerminalBehaviorCapability {
  const GrokTerminalBehavior();

  @override
  bool get supportsTurnInterrupt => true;

  @override
  TurnInterruptPlan get interruptPlan =>
      const TurnInterruptPlan(steps: ['\x03']);

  @override
  bool get usesFullScreenInput => false;

  @override
  Duration get fullScreenPasteSettleDelay => const Duration(milliseconds: 10);

  @override
  bool get usesGridPasteAck => false;

  @override
  bool get usesHookSubmitAck => false;

  @override
  bool get usesPasteBaseline => false;

  @override
  int get pasteZoneBottomPad => 0;

  @override
  TerminalPathDropBehavior get pathDropBehavior =>
      TerminalPathDropBehavior.defaultFor(usesFullScreenInput: false);

  @override
  FullscreenCrAckStrategy get fullscreenCrAckStrategy =>
      FullscreenCrAckStrategy.anchorCellClears;

  @override
  bool get mentionAutocompletePopup => false;

  @override
  FullscreenInputReadiness get inputReadiness =>
      FullscreenInputReadiness.bootFrameOnly;

  @override
  Duration get startupDeadline => const Duration(seconds: 15);
}
