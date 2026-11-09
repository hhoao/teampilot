import 'package:ai_message_ui/ai_message_ui.dart';

import '../../l10n/app_localizations.dart';

/// Maps app l10n into package [AiMessageStrings] (history chrome + live cards).
///
/// [permissionCliName] is the seat CLI label for permission-card chrome.
/// Omit it for transcript-only scopes that never show a permission card.
AiMessageStrings aiMessageStringsFromL10n(
  AppLocalizations l10n, {
  String? permissionCliName,
  bool thinkingProcessToolCalls = false,
}) {
  final cliName = permissionCliName?.trim() ?? '';
  return AiMessageStrings(
    usedTool: l10n.ai.messageUsedTool,
    cancelledTool: l10n.ai.messageCancelledTool,
    formatToolsUsed: (count) => l10n.ai.messageToolsUsed(count: count),
    reasoning: l10n.ai.messageReasoning,
    result: l10n.ai.messageToolResult,
    copy: l10n.copy,
    copied: l10n.ai.messageCopied,
    attachFile: l10n.workspace.chatLandingAttach,
    retryDelivery: l10n.session.historyRetry,
    exportMarkdown: l10n.ai.messageExportMarkdown,
    messageIncomplete: l10n.ai.messageIncomplete,
    messageCancelled: l10n.ai.messageCancelled,
    scrollToBottom: l10n.ai.messageScrollToBottom,
    showMore: l10n.ai.messageShowMore,
    showLess: l10n.ai.messageShowLess,
    thinkingProcess: l10n.ai.messageThinkingProcess,
    formatThinkingProcessSteps: (count) =>
        l10n.ai.messageThinkingProcessSteps(count: count as int),
    formatThinkingProcessSummary: (summary) =>
        _thinkingProcessSummaryLabel(l10n, summary),
    formatThinkingProcessStats: thinkingProcessToolCalls
        ? (steps, toolCalls) => l10n.ai.messageThinkingProcessStats(
            steps: steps,
            toolCalls: toolCalls,
          )
        : null,
    askUserAsking: l10n.askUserQuestionBubbleAsking,
    formatAskUserAsked: (count) =>
        l10n.askUserQuestionBubbleAsked(count: count as int),
    askUserUnanswered: l10n.askUserQuestionBubbleUnanswered,
    taskStatusPending: l10n.cli.taskStatusPending,
    taskStatusInProgress: l10n.cli.taskStatusInProgress,
    taskStatusCompleted: l10n.cli.taskStatusCompleted,
    taskStatusCancelled: l10n.cli.taskStatusCancelled,
    taskStatusUnknown: l10n.cli.taskStatusUnknown,
    workflowRunMissing: l10n.workflowCardRunMissing,
    formatWorkflowAgents: (count) =>
        l10n.workflowCardAgents(count: count as int),
    askUserAnswerInTerminal: l10n.agent.askAnswerInTerminal,
    askUserAnswerFailed: l10n.agent.askAnswerFailed,
    askUserTerminalDisconnected: l10n.agent.askTerminalDisconnected,
    askUserSubmit: l10n.agent.askSubmitAnswers,
    askUserContinue: l10n.agent.askContinue,
    askUserIgnore: l10n.agent.askIgnore,
    askUserKeyboardHint: l10n.agent.askKeyboardHint,
    askUserCustomHint: l10n.agent.askCustomAnswerHint,
    formatAskUserQuestionTab: (index) =>
        l10n.agent.askQuestionTabFallback(index: index as int),
    exitPlanTitle: l10n.exit.planModeTitle,
    exitPlanApprove: l10n.exit.planModeApprove,
    exitPlanReject: l10n.exit.planModeReject,
    exitPlanCopy: l10n.exit.planModeCopyPlan,
    exitPlanViewPlan: l10n.exit.planModeViewPlan,
    exitPlanPreviewTitle: l10n.exit.planModePreviewTitle,
    exitPlanOpenFile: l10n.exit.planModeOpenPlanFile,
    exitPlanApproveFailed: l10n.exit.planModeApproveFailed,
    exitPlanRejectFailed: l10n.exit.planModeRejectFailed,
    permissionOpenTerminal: l10n.agent.permissionOpenTerminal,
    permissionTitle: cliName.isEmpty
        ? l10n.agent.permissionTitleGeneric
        : l10n.agent.permissionTitle(cliName: cliName),
    permissionAllowOnce: l10n.opencode.permissionAllowOnce,
    permissionAllowAlways: l10n.opencode.permissionAllowAlways,
    permissionReject: l10n.opencode.permissionReject,
    permissionAnswerFailed: l10n.opencode.permissionAnswerFailed,
    permissionAnswerInTerminal: l10n.opencode.permissionAnswerInTerminal,
    taskBoardTitle: l10n.cli.taskBoardTitle,
    formatTaskBoardCount: (completed, total) => l10n.cli.taskBoardCount(
      completed: completed as int,
      total: total as int,
    ),
    formatTaskBoardMore: (count) => l10n.cli.taskBoardMore(count: count as int),
    taskBoardShowLess: l10n.cli.taskBoardShowLess,
  );
}

String _thinkingProcessSummaryLabel(
  AppLocalizations l10n,
  AiThinkingProcessSummary summary,
) {
  final parts = <String>[
    if (summary.editedFiles > 0)
      l10n.ai.messageThinkingEditedFiles(count: summary.editedFiles),
    if (summary.exploredFiles > 0)
      l10n.ai.messageThinkingExploredFiles(count: summary.exploredFiles),
    if (summary.searches > 0)
      l10n.ai.messageThinkingSearches(count: summary.searches),
    if (summary.commands > 0)
      l10n.ai.messageThinkingCommands(count: summary.commands),
  ];
  if (parts.isEmpty) return '';
  final joined = parts.join(l10n.ai.messageThinkingProcessSummarySeparator);
  return '${joined[0].toUpperCase()}${joined.substring(1)}';
}
