import '../../registry/capabilities/ask_user_question_capability.dart';

/// Cursor has no structured question payload (asks as plain terminal text).
final class NoAskUserQuestionCapability implements AskUserQuestionCapability {
  const NoAskUserQuestionCapability();

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
}
