import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/chat_interaction_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('claude family supports in-chat single-select pty', () {
    final reg = CliToolRegistry.builtIn();
    final cap = reg.capability<ChatInteractionCapability>(CliTool.claude)!;
    expect(cap.supportsStructuredAsk, isTrue);
    expect(cap.supportsInChatAnswer, isTrue);
    expect(cap.supportsMultiSelectInChat, isTrue);
    expect(cap.supportsMultiQuestionInChat, isTrue);
    expect(cap.supportsInChatPermissionReply, isFalse);
    expect(cap.answerKind, AskUserAnswerKind.ptyPicker);
    expect(cap.supportsInChatApproval, isTrue);
    expect(cap.approvalKind, ExitPlanApprovalKind.hookReply);
  });

  test('flashskyai supports in-chat single-select pty', () {
    final reg = CliToolRegistry.builtIn();
    final cap = reg.capability<ChatInteractionCapability>(CliTool.flashskyai)!;
    expect(cap.supportsStructuredAsk, isTrue);
    expect(cap.supportsInChatAnswer, isTrue);
    expect(cap.supportsMultiSelectInChat, isTrue);
    expect(cap.supportsMultiQuestionInChat, isTrue);
    expect(cap.supportsInChatPermissionReply, isFalse);
    expect(cap.answerKind, AskUserAnswerKind.ptyPicker);
    expect(cap.supportsInChatApproval, isTrue);
    expect(cap.approvalKind, ExitPlanApprovalKind.hookReply);
  });

  test('codex supports in-chat single-select pty', () {
    final reg = CliToolRegistry.builtIn();
    final cap = reg.capability<ChatInteractionCapability>(CliTool.codex)!;
    expect(cap.supportsStructuredAsk, isTrue);
    expect(cap.supportsInChatAnswer, isTrue);
    expect(cap.supportsMultiSelectInChat, isTrue);
    expect(cap.supportsMultiQuestionInChat, isTrue);
    expect(cap.supportsInChatPermissionReply, isFalse);
    expect(cap.answerKind, AskUserAnswerKind.ptyPicker);
    expect(cap.supportsInChatApproval, isFalse);
    expect(cap.approvalKind, ExitPlanApprovalKind.none);
  });

  test('opencode supports pluginSdkReply + multi', () {
    final reg = CliToolRegistry.builtIn();
    final cap = reg.capability<ChatInteractionCapability>(CliTool.opencode)!;
    expect(cap.supportsStructuredAsk, isTrue);
    expect(cap.supportsInChatAnswer, isTrue);
    expect(cap.supportsMultiSelectInChat, isTrue);
    expect(cap.supportsMultiQuestionInChat, isTrue);
    expect(cap.supportsInChatPermissionReply, isTrue);
    expect(cap.answerKind, AskUserAnswerKind.pluginSdkReply);
    expect(cap.supportsInChatApproval, isFalse);
    expect(cap.approvalKind, ExitPlanApprovalKind.none);
  });

  test('cursor has none / no in-chat', () {
    final reg = CliToolRegistry.builtIn();
    final cap = reg.capability<ChatInteractionCapability>(CliTool.cursor)!;
    expect(cap.supportsStructuredAsk, isFalse);
    expect(cap.supportsInChatAnswer, isFalse);
    expect(cap.supportsMultiSelectInChat, isFalse);
    expect(cap.supportsMultiQuestionInChat, isFalse);
    expect(cap.supportsInChatPermissionReply, isFalse);
    expect(cap.answerKind, AskUserAnswerKind.none);
    expect(cap.supportsInChatApproval, isFalse);
    expect(cap.approvalKind, ExitPlanApprovalKind.none);
  });
}
