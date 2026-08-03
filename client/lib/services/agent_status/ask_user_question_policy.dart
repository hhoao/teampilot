import 'package:teampilot/services/agent_status/ask_user_question.dart';
import 'package:teampilot/services/cli/registry/capabilities/ask_user_question_capability.dart';

/// Whether the chat should render an [AskUserQuestionCard] for the given
/// capability and parsed questions (vs a generic attention banner).
bool shouldShowAskUserQuestionCard({
  required AskUserQuestionCapability? capability,
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
