import 'package:flutter/foundation.dart';

import '../../cubits/chat/model/chat_state.dart';

/// Narrow projection of [ChatState] for [ChatWorkbench] layout — ignores
/// [ChatState.workingSessionIds] and other sidebar-only fields so agent-turn
/// polling does not rebuild the terminal subtree.
@immutable
class ChatWorkbenchSlice {
  const ChatWorkbenchSlice({
    required this.stateVersion,
    required this.activeSessionId,
    required this.selectedMemberId,
    required this.activeTabIndex,
    required this.tabCount,
    required this.sessionConnectingId,
    required this.sessionLaunchError,
  });

  factory ChatWorkbenchSlice.from(ChatState state) {
    return ChatWorkbenchSlice(
      stateVersion: state.stateVersion,
      activeSessionId: state.activeSessionId,
      selectedMemberId: state.selectedMemberId,
      activeTabIndex: state.activeTabIndex,
      tabCount: state.tabs.length,
      sessionConnectingId: state.sessionConnectingId,
      sessionLaunchError: state.sessionLaunchError,
    );
  }

  final int stateVersion;
  final String? activeSessionId;
  final String selectedMemberId;
  final int activeTabIndex;
  final int tabCount;
  final String? sessionConnectingId;
  final String? sessionLaunchError;

  bool get isActiveSessionConnecting {
    final id = sessionConnectingId;
    final active = activeSessionId;
    if (id == null || id.isEmpty) return false;
    if (id == 'pending') return true;
    if (active == null || active.isEmpty) return true;
    return id == active;
  }

  @override
  bool operator ==(Object other) {
    return other is ChatWorkbenchSlice &&
        stateVersion == other.stateVersion &&
        activeSessionId == other.activeSessionId &&
        selectedMemberId == other.selectedMemberId &&
        activeTabIndex == other.activeTabIndex &&
        tabCount == other.tabCount &&
        sessionConnectingId == other.sessionConnectingId &&
        sessionLaunchError == other.sessionLaunchError;
  }

  @override
  int get hashCode => Object.hash(
    stateVersion,
    activeSessionId,
    selectedMemberId,
    activeTabIndex,
    tabCount,
    sessionConnectingId,
    sessionLaunchError,
  );
}
