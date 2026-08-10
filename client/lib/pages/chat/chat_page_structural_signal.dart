import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../../cubits/chat/chat_tab_store.dart';
import '../../cubits/chat/model/chat_state.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';

/// Title-free structural tuple for [ChatPageShell] scoped tab rebuild gating.
///
/// Derived from the workbench bar (single source of strip order/active) plus the
/// session registry for per-workspace runtime state.
@immutable
class ChatPageStructuralSignal {
  const ChatPageStructuralSignal({
    required this.tabIds,
    required this.activeTabIndex,
    required this.newChatActive,
    required this.selectedMemberId,
    required this.sessionLaunchError,
    required this.pinnedBySessionId,
  });

  final List<String> tabIds;
  final int activeTabIndex;
  final bool newChatActive;
  final String selectedMemberId;
  final String? sessionLaunchError;
  final Map<String, bool> pinnedBySessionId;

  @override
  bool operator ==(Object other) {
    return other is ChatPageStructuralSignal &&
        const ListEquality<String>().equals(tabIds, other.tabIds) &&
        activeTabIndex == other.activeTabIndex &&
        newChatActive == other.newChatActive &&
        selectedMemberId == other.selectedMemberId &&
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
    sessionLaunchError,
    const MapEquality<String, bool>().hash(pinnedBySessionId),
  );
}

ChatPageStructuralSignal chatPageStructuralSignal({
  required ChatState state,
  required ChatTabStore tabStore,
  required WorkbenchCubit workbench,
  required String tabScopeId,
}) {
  final bar = workbench.state.bar(tabScopeId);
  final order = bar.center.order;
  final activeId = bar.center.activeId;
  final tabIds = [
    for (final t in order)
      if (t.kind == WorkbenchTabKind.session) t.id,
  ];
  final isForeground = tabStore.activeWorkspaceId == tabScopeId;
  final activeTab = activeId == null || activeId.kind != WorkbenchTabKind.session
      ? null
      : tabStore.openTabBySessionId(activeId.id);
  return ChatPageStructuralSignal(
    tabIds: tabIds,
    activeTabIndex: activeId == null ? -1 : order.indexOf(activeId),
    newChatActive: bar.center.landingActive,
    selectedMemberId: isForeground
        ? state.selectedMemberId
        : (activeTab?.selectedMemberId ?? ''),
    sessionLaunchError: isForeground
        ? state.sessionLaunchError
        : activeTab?.info.launchError,
    pinnedBySessionId: _pinnedForTabIds(state, tabIds),
  );
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
