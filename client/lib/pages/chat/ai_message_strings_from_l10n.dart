import 'package:ai_message_ui/ai_message_ui.dart';

import '../../l10n/app_localizations.dart';

/// Maps app l10n into package [AiMessageStrings] (history chrome + live cards).
AiMessageStrings aiMessageStringsFromL10n(AppLocalizations l10n) {
  return AiMessageStrings(
    usedTool: l10n.aiMessageUsedTool,
    cancelledTool: l10n.aiMessageCancelledTool,
    formatToolsUsed: l10n.aiMessageToolsUsed,
    reasoning: l10n.aiMessageReasoning,
    result: l10n.aiMessageToolResult,
    copy: l10n.copy,
    copied: l10n.aiMessageCopied,
    retryDelivery: l10n.sessionHistoryRetry,
    exportMarkdown: l10n.aiMessageExportMarkdown,
    messageIncomplete: l10n.aiMessageIncomplete,
    messageCancelled: l10n.aiMessageCancelled,
    scrollToBottom: l10n.aiMessageScrollToBottom,
    showMore: l10n.aiMessageShowMore,
    showLess: l10n.aiMessageShowLess,
    thinkingProcess: l10n.aiMessageThinkingProcess,
    formatThinkingProcessSteps: (count) =>
        l10n.aiMessageThinkingProcessSteps(count as int),
    formatThinkingProcessSummary: (summary) =>
        _thinkingProcessSummaryLabel(l10n, summary),
    askUserAsking: l10n.askUserQuestionBubbleAsking,
    formatAskUserAsked: (count) =>
        l10n.askUserQuestionBubbleAsked(count as int),
    askUserUnanswered: l10n.askUserQuestionBubbleUnanswered,
    taskStatusPending: l10n.cliTaskStatusPending,
    taskStatusInProgress: l10n.cliTaskStatusInProgress,
    taskStatusCompleted: l10n.cliTaskStatusCompleted,
    taskStatusCancelled: l10n.cliTaskStatusCancelled,
    taskStatusUnknown: l10n.cliTaskStatusUnknown,
    workflowRunMissing: l10n.workflowCardRunMissing,
    formatWorkflowAgents: (count) => l10n.workflowCardAgents(count as int),
    askUserAnswerInTerminal: l10n.agentAskAnswerInTerminal,
    askUserAnswerFailed: l10n.agentAskAnswerFailed,
    askUserTerminalDisconnected: l10n.agentAskTerminalDisconnected,
    askUserSubmit: l10n.agentAskSubmitAnswers,
    askUserContinue: l10n.agentAskContinue,
    askUserIgnore: l10n.agentAskIgnore,
    askUserKeyboardHint: l10n.agentAskKeyboardHint,
    askUserCustomHint: l10n.agentAskCustomAnswerHint,
    formatAskUserQuestionTab: (index) =>
        l10n.agentAskQuestionTabFallback(index as int),
    exitPlanTitle: l10n.exitPlanModeTitle,
    exitPlanApprove: l10n.exitPlanModeApprove,
    exitPlanReject: l10n.exitPlanModeReject,
    exitPlanCopy: l10n.exitPlanModeCopyPlan,
    exitPlanExpand: l10n.exitPlanModeExpand,
    exitPlanCollapse: l10n.exitPlanModeCollapse,
    exitPlanOpenFile: l10n.exitPlanModeOpenPlanFile,
    exitPlanApproveFailed: l10n.exitPlanModeApproveFailed,
    exitPlanRejectFailed: l10n.exitPlanModeRejectFailed,
    permissionOpenTerminal: l10n.agentPermissionOpenTerminal,
    permissionTitle: l10n.opencodePermissionTitle,
    permissionAllowOnce: l10n.opencodePermissionAllowOnce,
    permissionAllowAlways: l10n.opencodePermissionAllowAlways,
    permissionReject: l10n.opencodePermissionReject,
    permissionAnswerFailed: l10n.opencodePermissionAnswerFailed,
    permissionAnswerInTerminal: l10n.opencodePermissionAnswerInTerminal,
    taskBoardTitle: l10n.cliTaskBoardTitle,
    formatTaskBoardCount: (completed, total) =>
        l10n.cliTaskBoardCount(completed as int, total as int),
    formatTaskBoardMore: (count) => l10n.cliTaskBoardMore(count as int),
    taskBoardShowLess: l10n.cliTaskBoardShowLess,
  );
}

String _thinkingProcessSummaryLabel(
  AppLocalizations l10n,
  AiThinkingProcessSummary summary,
) {
  final parts = <String>[
    if (summary.editedFiles > 0)
      l10n.aiMessageThinkingEditedFiles(summary.editedFiles),
    if (summary.exploredFiles > 0)
      l10n.aiMessageThinkingExploredFiles(summary.exploredFiles),
    if (summary.searches > 0) l10n.aiMessageThinkingSearches(summary.searches),
    if (summary.commands > 0) l10n.aiMessageThinkingCommands(summary.commands),
  ];
  if (parts.isEmpty) return '';
  final joined = parts.join(l10n.aiMessageThinkingProcessSummarySeparator);
  return '${joined[0].toUpperCase()}${joined.substring(1)}';
}
