import '../../../agent_status/agent_status_event.dart';
import '../../registry/capabilities/chat_interaction_capability.dart';
import '../../registry/capabilities/claude_family_agent_status_normalizer.dart';

/// PTY picker answer flow — Claude Code surfaces AskUserQuestion through the
/// embedded terminal, and holds the `PreToolUse` HTTP hook to reply with the
/// official `permissionDecision` for ExitPlanMode approval.
final class ClaudeChatInteraction implements ChatInteractionCapability {
  const ClaudeChatInteraction();

  @override
  AgentStatusEvent? normalize(Map<String, Object?> body) =>
      const ClaudeFamilyAgentStatusNormalizer().normalize(body);

  @override
  bool get supportsStructuredAsk => true;

  @override
  bool get supportsInChatAnswer => true;

  @override
  bool get supportsMultiSelectInChat => true;

  @override
  bool get supportsMultiQuestionInChat => true;

  @override
  bool get supportsInChatPermissionReply => false;

  @override
  AskUserAnswerKind get answerKind => AskUserAnswerKind.ptyPicker;

  @override
  bool get supportsInChatApproval => true;

  @override
  ExitPlanApprovalKind get approvalKind => ExitPlanApprovalKind.hookReply;
}
