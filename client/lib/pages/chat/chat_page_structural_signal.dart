import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../../cubits/chat/model/chat_state.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat/chat_tab_store.dart';

/// Title-free structural tuple for [ChatPageShell] scoped tab rebuild gating.
@immutable
class ChatPageStructuralSignal {
  const ChatPageStructuralSignal({
    required this.tabIds,
    required this.activeTabIndex,
    required this.newChatActive,
    required this.selectedMemberId,
    required this.sessionConnectingId,
    required this.sessionLaunchError,
    required this.pinnedBySessionId,
  });

  final List<String> tabIds;
  final int activeTabIndex;
  final bool newChatActive;
  final String selectedMemberId;
  final String? sessionConnectingId;
  final String? sessionLaunchError;
  final Map<String, bool> pinnedBySessionId;

  @override
  bool operator ==(Object other) {
    return other is ChatPageStructuralSignal &&
        const ListEquality<String>().equals(tabIds, other.tabIds) &&
        activeTabIndex == other.activeTabIndex &&
        newChatActive == other.newChatActive &&
        selectedMemberId == other.selectedMemberId &&
        sessionConnectingId == other.sessionConnectingId &&
        sessionLaunchError == other.sessionLaunchError &&
        const MapEquality<String, bool>().equals(
          pinnedBySessionId,
          other.pinnedBySessionId,
        );
  }

  @override
  int get hashCode => Object.hash(
    const ListEquality<String>().hash(tabIds),
    activeTabIndex,
    newChatActive,
    selectedMemberId,
    sessionConnectingId,
    sessionLaunchError,
    const MapEquality<String, bool>().hash(pinnedBySessionId),
  );
}

ChatPageStructuralSignal chatPageStructuralSignal({
  required ChatState state,
  required ChatTabStore tabStore,
  required String tabScopeId,
}) {
  final isForeground = tabStore.activeWorkspaceId == tabScopeId;
  if (isForeground) {
    final tabIds = state.tabs.map((t) => t.id).toList(growable: false);
    return ChatPageStructuralSignal(
      tabIds: tabIds,
      activeTabIndex: state.activeTabIndex,
      newChatActive: state.newChatActive,
      selectedMemberId: state.selectedMemberId,
      sessionConnectingId: _scopedConnectingId(state, state.activeSessionId),
      sessionLaunchError: state.sessionLaunchError,
      pinnedBySessionId: _pinnedForTabIds(state, tabIds),
    );
  }

  final bucket = tabStore.tabsForWorkspace(tabScopeId);
  final index = tabStore.savedActiveIndexFor(tabScopeId);
  final newChatActive = tabStore.isNewChatActive(tabScopeId);
  final ChatTab? tab = bucket.isEmpty || newChatActive
      ? null
      : bucket[index.clamp(0, bucket.length - 1)];
  final tabIds = bucket.map((t) => t.info.id).toList(growable: false);
  final activeSessionId = tab?.info.id;
  return ChatPageStructuralSignal(
    tabIds: tabIds,
    activeTabIndex: index,
    newChatActive: newChatActive,
    selectedMemberId: tab?.selectedMemberId ?? '',
    sessionConnectingId:
        activeSessionId != null && state.sessionConnectingId == activeSessionId
        ? state.sessionConnectingId
        : null,
    sessionLaunchError: tab?.info.launchError,
    pinnedBySessionId: _pinnedForTabIds(state, tabIds),
  );
}

String? _scopedConnectingId(ChatState state, String? activeSessionId) {
  final id = state.sessionConnectingId;
  if (id == null || id.isEmpty) return null;
  if (id == 'pending') return id;
  if (activeSessionId == null || activeSessionId.isEmpty) return null;
  return id == activeSessionId ? id : null;
}

Map<String, bool> _pinnedForTabIds(ChatState state, List<String> tabIds) {
  final ids = tabIds.toSet();
  final pinned = <String, bool>{};
  for (final session in state.sessions) {
    if (ids.contains(session.sessionId)) {
      pinned[session.sessionId] = session.pinned;
    }
  }
  return pinned;
}
