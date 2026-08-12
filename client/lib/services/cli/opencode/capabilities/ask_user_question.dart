import '../../registry/capabilities/ask_user_question_capability.dart';

/// OpenCode answers questions through the plugin SDK (and `permission.asked`
/// allow/deny replies from the chat card).
final class OpenCodeAskUserQuestionCapability
    implements AskUserQuestionCapability {
  const OpenCodeAskUserQuestionCapability();

  @override
  bool get supportsStructuredAsk => true;

  @override
  bool get supportsInChatAnswer => true;

  @override
  bool get supportsMultiSelectInChat => true;

  @override
  bool get supportsMultiQuestionInChat => true;

  @override
  bool get supportsInChatPermissionReply => true;

  @override
  AskUserAnswerKind get answerKind => AskUserAnswerKind.pluginSdkReply;
}
