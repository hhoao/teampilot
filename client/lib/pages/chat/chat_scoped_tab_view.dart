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
    required this.workingSessionIds,
    required this.selectedMemberId,
    required this.workbenchSlice,
  });

  final List<ChatTabInfo> tabs;
  final int activeTabIndex;
  final Set<String> workingSessionIds;
  final String selectedMemberId;
  final ChatWorkbenchSlice workbenchSlice;

  static const _listEquality = ListEquality<ChatTabInfo>();
  static const _setEquality = SetEquality<String>();

  static ChatScopedTabView resolve(ChatCubit cubit, String workspaceTabKey) {
    final state = cubit.state;
    final store = cubit.tabStore;
    final isForeground = store.activeWorkspaceId == workspaceTabKey;
    if (isForeground) {
      final bucketIds = store.tabs.map((t) => t.info.id).toSet();
      return ChatScopedTabView(
        tabs: state.tabs,
        activeTabIndex: state.activeTabIndex,
        workingSessionIds: state.workingSessionIds
            .where(bucketIds.contains)
            .toSet(),
        selectedMemberId: state.selectedMemberId,
        workbenchSlice: ChatWorkbenchSlice.from(state),
      );
    }

    final bucket = store.tabsForWorkspace(workspaceTabKey);
    final index = store.savedActiveIndexFor(workspaceTabKey);
    final ChatTab? tab = bucket.isEmpty
        ? null
        : bucket[index.clamp(0, bucket.length - 1)];
    final bucketIds = bucket.map((t) => t.info.id).toSet();
    final activeSessionId = tab?.info.id;
    return ChatScopedTabView(
      tabs: bucket.map((t) => t.info).toList(),
      activeTabIndex: index,
      workingSessionIds: state.workingSessionIds
          .where(bucketIds.contains)
          .toSet(),
      selectedMemberId: tab?.selectedMemberId ?? '',
      workbenchSlice: ChatWorkbenchSlice(
        stateVersion: state.stateVersion,
        activeSessionId: activeSessionId,
        selectedMemberId: tab?.selectedMemberId ?? '',
        activeTabIndex: index,
        tabCount: bucket.length,
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
            _setEquality.equals(workingSessionIds, other.workingSessionIds) &&
            selectedMemberId == other.selectedMemberId &&
            workbenchSlice == other.workbenchSlice;
  }

  @override
  int get hashCode => Object.hash(
    _listEquality.hash(tabs),
    activeTabIndex,
    _setEquality.hash(workingSessionIds),
    selectedMemberId,
    workbenchSlice,
  );
}
