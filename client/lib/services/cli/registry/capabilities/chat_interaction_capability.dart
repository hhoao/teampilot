import '../../../agent_status/agent_status_event.dart';
import '../cli_capability.dart';

enum AskUserAnswerKind { ptyPicker, pluginSdkReply, none }

/// How a CLI resolves an in-chat ExitPlanMode approval.
enum ExitPlanApprovalKind { hookReply, none }

/// Chat interaction: reports seat attention to chat, asks the user questions,
/// and receives ExitPlanMode approval.
///
/// Each CLI implements its own payload grammar in its own directory
/// (claude/codex/flashskyai share the [ClaudeFamilyAgentStatusNormalizer]);
/// the shared [AgentStatusNormalizer] facade only looks this capability up.
/// claude + flashskyai hold the `PreToolUse` HTTP hook and reply with the
/// official `permissionDecision`. Other CLIs keep the "Open Terminal" fallback.
abstract interface class ChatInteractionCapability implements CliCapability {
  /// Returns `null` for corrupt or unknown payloads.
  AgentStatusEvent? normalize(Map<String, Object?> body);

  bool get supportsStructuredAsk;
  bool get supportsInChatAnswer;

  /// Checkbox-style multi-select within a single question (OpenCode).
  bool get supportsMultiSelectInChat;

  /// Multiple questions in one AskUserQuestion / question.asked payload.
  bool get supportsMultiQuestionInChat;

  /// OpenCode `permission.asked` allow/deny reply from the chat card.
  bool get supportsInChatPermissionReply;

  AskUserAnswerKind get answerKind;

  bool get supportsInChatApproval;
  ExitPlanApprovalKind get approvalKind;
}
