import '../cli_capability.dart';
import 'ask_user_question_capability.dart';

/// PTY picker answer flow — shared by the claude-family CLIs (claude, codex,
/// flashskyai) which surface AskUserQuestion through the embedded terminal.
final class PtyAskUserQuestionCapability implements AskUserQuestionCapability {
  const PtyAskUserQuestionCapability();

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
}
