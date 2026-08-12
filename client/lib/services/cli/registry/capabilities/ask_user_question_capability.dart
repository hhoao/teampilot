import '../cli_capability.dart';

enum AskUserAnswerKind { ptyPicker, pluginSdkReply, none }

abstract interface class AskUserQuestionCapability implements CliCapability {
  bool get supportsStructuredAsk;
  bool get supportsInChatAnswer;

  /// Checkbox-style multi-select within a single question (OpenCode).
  bool get supportsMultiSelectInChat;

  /// Multiple questions in one AskUserQuestion / question.asked payload.
  bool get supportsMultiQuestionInChat;

  /// OpenCode `permission.asked` allow/deny reply from the chat card.
  bool get supportsInChatPermissionReply;

  AskUserAnswerKind get answerKind;
}

