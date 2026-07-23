import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/chat/model/chat_tab.dart';
import 'chat_workbench_slice.dart';

/// Per–title-bar-tab projection of open chat tabs + workbench slice. Used when
/// multiple [WorkspacePage]s are kept alive so background tabs do not read the
/// active workspace bucket from [ChatState].
@immutable
class ChatScopedTabView {
  const ChatScopedTabView({
    required this.tabs,
    required this.activeTabIndex,
    required this.selectedMemberId,
    required this.newChatActive,
    required this.workbenchSlice,
  });

  final List<ChatTabInfo> tabs;
  final int activeTabIndex;
  final String selectedMemberId;
  final bool newChatActive;
  final ChatWorkbenchSlice workbenchSlice;

  static const _listEquality = ListEquality<ChatTabInfo>();

  static ChatScopedTabView resolve(ChatCubit cubit, String workspaceTabKey) {
    final state = cubit.state;
    final store = cubit.tabStore;
    final isForeground = store.activeWorkspaceId == workspaceTabKey;
    if (isForeground) {
      return ChatScopedTabView(
        tabs: state.tabs,
        activeTabIndex: state.activeTabIndex,
        selectedMemberId: state.selectedMemberId,
        newChatActive: state.newChatActive,
        workbenchSlice: ChatWorkbenchSlice.from(state),
      );
    }

    final bucket = store.tabsForWorkspace(workspaceTabKey);
    final index = store.savedActiveIndexFor(workspaceTabKey);
    final newChatActive = store.isNewChatActive(workspaceTabKey);
    final ChatTab? tab = bucket.isEmpty || newChatActive
        ? null
        : bucket[index.clamp(0, bucket.length - 1)];
    final activeSessionId = tab?.info.id;
    return ChatScopedTabView(
      tabs: bucket.map((t) => t.info).toList(),
      activeTabIndex: index,
      selectedMemberId: tab?.selectedMemberId ?? '',
      newChatActive: newChatActive,
      workbenchSlice: ChatWorkbenchSlice(
        stateVersion: state.stateVersion,
        activeSessionId: activeSessionId,
        selectedMemberId: tab?.selectedMemberId ?? '',
        activeTabIndex: index,
        tabCount: bucket.length,
        newChatActive: newChatActive,
        sessionConnectingId:
            activeSessionId != null &&
                state.sessionConnectingId == activeSessionId
            ? state.sessionConnectingId
            : null,
        sessionLaunchError: tab?.info.launchError,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ChatScopedTabView &&
            _listEquality.equals(tabs, other.tabs) &&
            activeTabIndex == other.activeTabIndex &&
            selectedMemberId == other.selectedMemberId &&
            newChatActive == other.newChatActive &&
            workbenchSlice == other.workbenchSlice;
  }

  @override
  int get hashCode => Object.hash(
    _listEquality.hash(tabs),
    activeTabIndex,
    selectedMemberId,
    newChatActive,
    workbenchSlice,
  );
}
