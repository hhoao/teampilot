import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/foundation.dart';

import '../../l10n/app_localizations.dart';

/// Debug-only counters for the [aiMessageStringsFromL10n] memo.
///
/// `AiMessageStringsScope` notifies descendants by identity, so a memo miss on
/// the transcript path dirties every chain-of-thought header. When a profile
/// snapshot shows unexplained rebuilds, run a debug `flutter run` and read the
/// `[perf]` line: misses climbing while the app sits on one locale means the
/// memo key is not matching.
class AiMessageStringsCacheStats {
  int hits = 0;
  int misses = 0;
  int evictions = 0;

  @override
  String toString() =>
      'strings-memo hits=$hits misses=$misses evictions=$evictions';
}

final AiMessageStringsCacheStats aiMessageStringsCacheStats =
    AiMessageStringsCacheStats();

/// Throttles the `[perf]` line so a streaming session prints ~once per 3 s.
DateTime _lastStringsStatsReport = DateTime.fromMillisecondsSinceEpoch(0);

void _reportStringsStats() {
  final now = DateTime.now();
  if (now.difference(_lastStringsStatsReport).inSeconds < 3) return;
  _lastStringsStatsReport = now;
  debugPrint('[perf] $aiMessageStringsCacheStats');
}

/// Maps app l10n into package [AiMessageStrings] (history chrome + live cards).
///
/// [permissionCliName] is the seat CLI label for permission-card chrome.
/// Omit it for transcript-only scopes that never show a permission card.
///
/// The result is memoized: the transcript host rebuilds on every streamed
/// chunk, and `AiMessageStringsScope` notifies descendants by identity, so
/// returning a fresh instance each build would mark every chain-of-thought
/// block, tool card and markdown view dirty on every frame.
AiMessageStrings aiMessageStringsFromL10n(
  AppLocalizations l10n, {
  String? permissionCliName,
  bool thinkingProcessToolCalls = false,
}) {
  final cliName = permissionCliName?.trim() ?? '';
  // Keyed by locale, not by the [AppLocalizations] instance: hosts resolve l10n
  // through different paths (Localizations lookup vs slang's provider) and can
  // hand back a fresh instance per build. Instance identity would then miss on
  // every frame and defeat the whole point of the cache.
  final key = _AiMessageStringsKey(
    l10n.localeName,
    cliName,
    thinkingProcessToolCalls,
  );
  final cached = _aiMessageStringsCache[key];
  if (cached != null) {
    assert(() {
      aiMessageStringsCacheStats.hits++;
      _reportStringsStats();
      return true;
    }());
    return cached;
  }
  assert(() {
    aiMessageStringsCacheStats.misses++;
    _reportStringsStats();
    return true;
  }());
  final strings = _buildAiMessageStrings(
    l10n,
    cliName: cliName,
    thinkingProcessToolCalls: thinkingProcessToolCalls,
  );
  if (_aiMessageStringsCache.length >= _aiMessageStringsCacheLimit) {
    _aiMessageStringsCache.remove(_aiMessageStringsCache.keys.first);
    assert(() {
      aiMessageStringsCacheStats.evictions++;
      return true;
    }());
  }
  _aiMessageStringsCache[key] = strings;
  return strings;
}

/// Small bound: one entry per (locale, CLI label, stats flag) is normally
/// enough, and a stale entry only costs memory after a locale switch.
const int _aiMessageStringsCacheLimit = 8;

final Map<_AiMessageStringsKey, AiMessageStrings> _aiMessageStringsCache = {};

class _AiMessageStringsKey {
  const _AiMessageStringsKey(
    this.localeName,
    this.cliName,
    this.thinkingProcessToolCalls,
  );

  final String localeName;
  final String cliName;
  final bool thinkingProcessToolCalls;

  @override
  bool operator ==(Object other) =>
      other is _AiMessageStringsKey &&
      other.localeName == localeName &&
      other.cliName == cliName &&
      other.thinkingProcessToolCalls == thinkingProcessToolCalls;

  @override
  int get hashCode =>
      Object.hash(localeName, cliName, thinkingProcessToolCalls);
}

AiMessageStrings _buildAiMessageStrings(
  AppLocalizations l10n, {
  required String cliName,
  required bool thinkingProcessToolCalls,
}) {
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
