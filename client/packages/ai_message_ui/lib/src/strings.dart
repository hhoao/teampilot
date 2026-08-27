import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import 'thinking_process_summary.dart';

/// Host-injected copy for ai_message_ui (package stays l10n-free).
@immutable
class AiMessageStrings {
  const AiMessageStrings({
    this.usedTool = 'Used tool',
    this.cancelledTool = 'Cancelled tool',
    this.formatToolsUsed = _defaultToolsUsed,
    this.reasoning = 'Reasoning',
    this.result = 'Result',
    this.copy = 'Copy',
    this.copied = 'Copied',
    this.retryDelivery = 'Retry',
    this.exportMarkdown = 'Export Markdown',
    this.code = 'code',
    this.messageIncomplete = 'Message incomplete',
    this.messageCancelled = 'Message cancelled',
    this.scrollToBottom = 'Scroll to bottom',
    this.showMore = 'Show more',
    this.showLess = 'Show less',
    this.thinkingProcess = 'Thinking process',
    this.formatThinkingProcessSteps = _defaultThinkingProcessSteps,
    this.formatThinkingProcessSummary = defaultThinkingProcessSummaryLabel,
    this.askUserAsking = 'Asking questions',
    this.formatAskUserAsked = _defaultAskUserAsked,
    this.askUserUnanswered = 'Unanswered',
    this.taskStatusPending = 'Pending',
    this.taskStatusInProgress = 'In progress',
    this.taskStatusCompleted = 'Done',
    this.taskStatusCancelled = 'Cancelled',
    this.taskStatusUnknown = 'Unknown',
    this.workflowRunMissing = 'Workflow run not found for this tool call.',
    this.formatWorkflowAgents = _defaultWorkflowAgents,
    this.askUserAnswerInTerminal = 'Answer in terminal',
    this.askUserAnswerFailed =
        'Couldn\'t submit your answer. Try again or answer in the Terminal.',
    this.askUserTerminalDisconnected =
        'Terminal is disconnected. Reconnect or answer in the Terminal.',
    this.askUserSubmit = 'Submit',
    this.askUserContinue = 'Continue',
    this.askUserIgnore = 'Ignore',
    this.askUserKeyboardHint =
        'Use Tab / ↑↓ to select, Enter or Space to confirm',
    this.askUserCustomHint = 'Enter your answer…',
    this.formatAskUserQuestionTab = _defaultAskUserQuestionTab,
    this.exitPlanTitle = 'Plan ready for approval',
    this.exitPlanApprove = 'Approve',
    this.exitPlanReject = 'Reject',
    this.exitPlanCopy = 'Copy plan',
    this.exitPlanExpand = 'Expand',
    this.exitPlanCollapse = 'Collapse',
    this.exitPlanOpenFile = 'Open plan file',
    this.exitPlanApproveFailed = 'Couldn\'t approve the plan',
    this.exitPlanRejectFailed = 'Couldn\'t reject the plan',
    this.permissionOpenTerminal = 'Open Terminal',
    this.permissionTitle = 'OpenCode needs your permission',
    this.permissionAllowOnce = 'Allow once',
    this.permissionAllowAlways = 'Always allow',
    this.permissionReject = 'Reject',
    this.permissionAnswerFailed =
        'Couldn\'t submit your decision. Try again or answer in the Terminal.',
    this.permissionAnswerInTerminal = 'Answer in terminal',
    this.taskBoardTitle = 'Tasks',
    this.formatTaskBoardCount = _defaultTaskBoardCount,
    this.formatTaskBoardMore = _defaultTaskBoardMore,
    this.taskBoardShowLess = 'Show less',
  });

  final String usedTool;
  final String cancelledTool;
  final String Function(Object count) formatToolsUsed;
  final String thinkingProcess;
  final String Function(Object count) formatThinkingProcessSteps;
  final AiThinkingProcessSummaryFormatter formatThinkingProcessSummary;
  final String reasoning;
  final String result;
  final String copy;
  final String copied;
  final String retryDelivery;
  final String exportMarkdown;
  final String code;
  final String messageIncomplete;
  final String messageCancelled;
  final String scrollToBottom;
  final String showMore;
  final String showLess;
  final String askUserAsking;
  final String Function(Object count) formatAskUserAsked;
  final String askUserUnanswered;
  final String taskStatusPending;
  final String taskStatusInProgress;
  final String taskStatusCompleted;
  final String taskStatusCancelled;
  final String taskStatusUnknown;
  final String workflowRunMissing;
  final String Function(Object count) formatWorkflowAgents;
  final String askUserAnswerInTerminal;
  final String askUserAnswerFailed;
  final String askUserTerminalDisconnected;
  final String askUserSubmit;
  final String askUserContinue;
  final String askUserIgnore;
  final String askUserKeyboardHint;
  final String askUserCustomHint;
  final String Function(Object index) formatAskUserQuestionTab;
  final String exitPlanTitle;
  final String exitPlanApprove;
  final String exitPlanReject;
  final String exitPlanCopy;
  final String exitPlanExpand;
  final String exitPlanCollapse;
  final String exitPlanOpenFile;
  final String exitPlanApproveFailed;
  final String exitPlanRejectFailed;
  final String permissionOpenTerminal;
  final String permissionTitle;
  final String permissionAllowOnce;
  final String permissionAllowAlways;
  final String permissionReject;
  final String permissionAnswerFailed;
  final String permissionAnswerInTerminal;
  final String taskBoardTitle;
  final String Function(Object completed, Object total) formatTaskBoardCount;
  final String Function(Object count) formatTaskBoardMore;
  final String taskBoardShowLess;

  String toolsUsedLabel(int count) => formatToolsUsed(count);

  String askUserAskedLabel(int count) => formatAskUserAsked(count);

  String workflowAgentsLabel(int count) => formatWorkflowAgents(count);

  String taskBoardCountLabel(int completed, int total) =>
      formatTaskBoardCount(completed, total);

  String taskBoardMoreLabel(int count) => formatTaskBoardMore(count);

  String askUserQuestionTabLabel(int index) => formatAskUserQuestionTab(index);

  String askUserFailureLabel(String reason) => switch (reason) {
    'terminal_disconnected' => askUserTerminalDisconnected,
    _ => askUserAnswerFailed,
  };

  String taskStatusLabel(AiTaskStatus status) => switch (status) {
    AiTaskStatus.pending => taskStatusPending,
    AiTaskStatus.inProgress => taskStatusInProgress,
    AiTaskStatus.completed => taskStatusCompleted,
    AiTaskStatus.cancelled => taskStatusCancelled,
    AiTaskStatus.unknown => taskStatusUnknown,
  };

  static String _defaultToolsUsed(Object count) => 'Used $count tools';

  static String _defaultThinkingProcessSteps(Object count) =>
      'Thinking process · $count steps';

  static String _defaultAskUserAsked(Object count) {
    final n = count is int ? count : int.tryParse('$count') ?? 0;
    return n == 1 ? 'Asked 1 question' : 'Asked $n questions';
  }

  static String _defaultWorkflowAgents(Object count) => '$count agents';

  static String _defaultAskUserQuestionTab(Object index) => 'Q$index';

  static String _defaultTaskBoardCount(Object completed, Object total) =>
      '$completed/$total';

  static String _defaultTaskBoardMore(Object count) => '… +$count more';

  static AiMessageStrings of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_AiMessageStringsScope>()
            ?.strings ??
        const AiMessageStrings();
  }
}

class AiMessageStringsScope extends StatelessWidget {
  const AiMessageStringsScope({
    required this.strings,
    required this.child,
    super.key,
  });

  final AiMessageStrings strings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _AiMessageStringsScope(strings: strings, child: child);
  }
}

class _AiMessageStringsScope extends InheritedWidget {
  const _AiMessageStringsScope({required this.strings, required super.child});

  final AiMessageStrings strings;

  @override
  bool updateShouldNotify(_AiMessageStringsScope oldWidget) =>
      !identical(strings, oldWidget.strings);
}
