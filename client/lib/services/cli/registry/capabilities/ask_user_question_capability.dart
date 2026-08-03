import '../cli_capability.dart';

enum AskUserAnswerKind { ptyPicker, pluginSdkReply, none }

abstract interface class AskUserQuestionCapability implements CliCapability {
  bool get supportsStructuredAsk;
  bool get supportsInChatAnswer;
  bool get supportsMultiSelectInChat;
  AskUserAnswerKind get answerKind;
}

final class PtyAskUserQuestionCapability implements AskUserQuestionCapability {
  const PtyAskUserQuestionCapability();

  @override
  bool get supportsStructuredAsk => true;

  @override
  bool get supportsInChatAnswer => true;

  @override
  bool get supportsMultiSelectInChat => false;

  @override
  AskUserAnswerKind get answerKind => AskUserAnswerKind.ptyPicker;
}

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
  AskUserAnswerKind get answerKind => AskUserAnswerKind.pluginSdkReply;
}

final class NoAskUserQuestionCapability implements AskUserQuestionCapability {
  const NoAskUserQuestionCapability();

  @override
  bool get supportsStructuredAsk => false;

  @override
  bool get supportsInChatAnswer => false;

  @override
  bool get supportsMultiSelectInChat => false;

  @override
  AskUserAnswerKind get answerKind => AskUserAnswerKind.none;
}
