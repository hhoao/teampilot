import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/ask_user_question_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('claude family supports in-chat single-select pty', () {
    final reg = CliToolRegistry.builtIn();
    final cap = reg.capability<AskUserQuestionCapability>(CliTool.claude)!;
    expect(cap.supportsStructuredAsk, isTrue);
    expect(cap.supportsInChatAnswer, isTrue);
    expect(cap.supportsMultiSelectInChat, isTrue);
    expect(cap.supportsMultiQuestionInChat, isTrue);
    expect(cap.answerKind, AskUserAnswerKind.ptyPicker);
  });

  test('flashskyai supports in-chat single-select pty', () {
    final reg = CliToolRegistry.builtIn();
    final cap = reg.capability<AskUserQuestionCapability>(CliTool.flashskyai)!;
    expect(cap.supportsStructuredAsk, isTrue);
    expect(cap.supportsInChatAnswer, isTrue);
    expect(cap.supportsMultiSelectInChat, isTrue);
    expect(cap.supportsMultiQuestionInChat, isTrue);
    expect(cap.answerKind, AskUserAnswerKind.ptyPicker);
  });

  test('codex supports in-chat single-select pty', () {
    final reg = CliToolRegistry.builtIn();
    final cap = reg.capability<AskUserQuestionCapability>(CliTool.codex)!;
    expect(cap.supportsStructuredAsk, isTrue);
    expect(cap.supportsInChatAnswer, isTrue);
    expect(cap.supportsMultiSelectInChat, isTrue);
    expect(cap.supportsMultiQuestionInChat, isTrue);
    expect(cap.answerKind, AskUserAnswerKind.ptyPicker);
  });

  test('opencode supports pluginSdkReply + multi', () {
    final reg = CliToolRegistry.builtIn();
    final cap = reg.capability<AskUserQuestionCapability>(CliTool.opencode)!;
    expect(cap.supportsStructuredAsk, isTrue);
    expect(cap.supportsInChatAnswer, isTrue);
    expect(cap.supportsMultiSelectInChat, isTrue);
    expect(cap.supportsMultiQuestionInChat, isTrue);
    expect(cap.answerKind, AskUserAnswerKind.pluginSdkReply);
  });

  test('cursor has none / no in-chat', () {
    final reg = CliToolRegistry.builtIn();
    final cap = reg.capability<AskUserQuestionCapability>(CliTool.cursor)!;
    expect(cap.supportsStructuredAsk, isFalse);
    expect(cap.supportsInChatAnswer, isFalse);
    expect(cap.supportsMultiSelectInChat, isFalse);
    expect(cap.supportsMultiQuestionInChat, isFalse);
    expect(cap.answerKind, AskUserAnswerKind.none);
  });
}
