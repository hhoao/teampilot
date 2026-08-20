import 'agent_permission_request.dart';
import 'ask_user_question.dart';
import '../cli/registry/capabilities/chat_interaction_capability.dart';

/// Whether the chat should render an OpenCode permission card (allow once /
/// always / reject) for the given capability and parsed permission payload
/// (vs a generic attention banner).
bool shouldShowPermissionCard({
  required ChatInteractionCapability? capability,
  required AgentPermissionRequest? permissionRequest,
  String? askRequestId,
}) {
  if (capability == null || !capability.supportsInChatPermissionReply) {
    return false;
  }

  if (permissionRequest == null) {
    return false;
  }

  // Correlating the reply back to opencode needs the permission request id.
  if (askRequestId == null || askRequestId.isEmpty) {
    return false;
  }

  return true;
}

/// Whether the chat should render an interactive ask-user card for the given
/// capability and parsed questions (vs a generic attention banner).
bool shouldShowAskUserQuestionCard({
  required ChatInteractionCapability? capability,
  required List<AgentAskUserQuestion>? questions,
  String? askRequestId,
}) {
  if (capability == null || !capability.supportsInChatAnswer) {
    return false;
  }

  if (questions == null || questions.isEmpty) {
    return false;
  }

  if (questions.any((q) => q.options.isEmpty)) {
    return false;
  }

  if (questions.any((q) => q.multiSelect) &&
      !capability.supportsMultiSelectInChat) {
    return false;
  }

  if (questions.length > 1 && !capability.supportsMultiQuestionInChat) {
    return false;
  }

  if (capability.answerKind == AskUserAnswerKind.pluginSdkReply &&
      (askRequestId == null || askRequestId.isEmpty)) {
    return false;
  }

  return true;
}
