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

  final needsMultiSupport =
      questions.length > 1 || questions.any((q) => q.multiSelect);

  if (needsMultiSupport) {
    if (!capability.supportsMultiSelectInChat) {
      return false;
    }
  } else {
    if (questions.single.options.isEmpty) {
      return false;
    }
  }

  if (capability.answerKind == AskUserAnswerKind.pluginSdkReply &&
      (askRequestId == null || askRequestId.isEmpty)) {
    return false;
  }

  return true;
}
