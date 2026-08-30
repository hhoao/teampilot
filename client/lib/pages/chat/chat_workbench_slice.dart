import 'package:flutter/foundation.dart';

import '../../cubits/chat/model/chat_state.dart';

/// Narrow projection of [ChatState] for [ChatWorkbench] layout — ignores
/// [ChatState.sessionActivities], [ChatState.provisionVersion], and other
/// sidebar-only / transient fields so agent-turn polling does not rebuild the
/// terminal subtree.
@immutable
class ChatWorkbenchSlice {
  const ChatWorkbenchSlice({
    required this.activeSessionId,
    required this.selectedMemberId,
    required this.sessionLaunchError,
  });

  /// Builds a slice from the scoped bar source: [activeSessionId] and
  /// [selectedMemberId] must come from `scopedActiveSessionId` /
  /// `scopedSelectedMemberId` (Task 1), never from [ChatState] mirrors.
  factory ChatWorkbenchSlice.fromScope({
    required ChatState state,
    required String? activeSessionId,
    required String selectedMemberId,
  }) {
    return ChatWorkbenchSlice(
      activeSessionId: activeSessionId,
      selectedMemberId: selectedMemberId,
      sessionLaunchError: state.sessionLaunchError,
    );
  }

  final String? activeSessionId;
  final String selectedMemberId;
  final String? sessionLaunchError;

  @override
  bool operator ==(Object other) {
    return other is ChatWorkbenchSlice &&
        activeSessionId == other.activeSessionId &&
        selectedMemberId == other.selectedMemberId &&
        sessionLaunchError == other.sessionLaunchError;
  }

  @override
  int get hashCode => Object.hash(
    activeSessionId,
    selectedMemberId,
    sessionLaunchError,
  );
}
