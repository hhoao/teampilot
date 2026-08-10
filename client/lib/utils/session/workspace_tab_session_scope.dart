import '../../cubits/chat_cubit.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../services/team_bus/team_bus.dart';

/// Session id highlighted in a kept-alive workspace sidebar for [tabScopeId].
///
/// The workbench bar is the single source of truth for the per-workspace active
/// tab, so the same lookup serves foreground and background workspaces: the
/// center-active session id (or null when landing / a file-diff tab is active).
String? scopedActiveSessionId(WorkbenchCubit workbench, String tabScopeId) =>
    workbench.centerActiveId(tabScopeId)?.sessionId;

/// Active [ChatTab] runtime for a kept-alive workspace tab.
///
/// Mirrors [scopedActiveSessionId] but resolves the runtime from the registry.
ChatTab? scopedActiveChatTab(
  WorkbenchCubit workbench,
  ChatCubit chat,
  String tabScopeId,
) {
  final sessionId = workbench.centerActiveId(tabScopeId)?.sessionId;
  if (sessionId == null) return null;
  return chat.tabStore.openTabBySessionId(sessionId);
}

TeamBus? scopedTeamBus(
  WorkbenchCubit workbench,
  ChatCubit chat,
  String tabScopeId,
) =>
    scopedActiveChatTab(workbench, chat, tabScopeId)?.teamBus;
