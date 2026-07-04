import '../cubits/chat_cubit.dart';
import '../cubits/chat/model/chat_tab.dart';
import '../services/team_bus/team_bus.dart';

/// Session id highlighted in a kept-alive workspace sidebar for [tabScopeId].
///
/// Foreground tabs follow [ChatState.activeSessionId]; background tabs freeze
/// to the bucket's saved active chat tab.
String? scopedActiveSessionId(ChatCubit cubit, String tabScopeId) {
  final store = cubit.tabStore;
  if (store.activeWorkspaceId == tabScopeId) {
    if (cubit.state.composeActive) return null;
    return cubit.state.activeSessionId;
  }
  if (store.isComposeActive(tabScopeId)) return null;
  final bucket = store.tabsForWorkspace(tabScopeId);
  if (bucket.isEmpty) return null;
  final index = store.savedActiveIndexFor(tabScopeId);
  return bucket[index.clamp(0, bucket.length - 1)].info.id;
}

/// Active [ChatTab] for a kept-alive title-bar workspace tab.
///
/// Foreground tabs follow [ChatState]; background tabs freeze to the bucket's
/// saved active index — same rules as [scopedActiveSessionId].
ChatTab? scopedActiveChatTab(ChatCubit cubit, String tabScopeId) {
  final store = cubit.tabStore;
  if (store.activeWorkspaceId == tabScopeId) {
    return store.activeTab(cubit.state.activeTabIndex);
  }
  final bucket = store.tabsForWorkspace(tabScopeId);
  if (bucket.isEmpty) return null;
  final index = store.savedActiveIndexFor(tabScopeId);
  return bucket[index.clamp(0, bucket.length - 1)];
}

TeamBus? scopedTeamBus(ChatCubit cubit, String tabScopeId) =>
    scopedActiveChatTab(cubit, tabScopeId)?.teamBus;
