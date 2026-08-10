import 'package:flutter/foundation.dart';

import '../../cubits/chat/model/chat_state.dart';

/// Narrow projection of [ChatState] for [ChatWorkbench] layout — ignores
/// [ChatState.workingSessionIds], [ChatState.provisionVersion], and other
/// sidebar-only / transient fields so agent-turn polling does not rebuild the
/// terminal subtree.
@immutable
class ChatWorkbenchSlice {
  const ChatWorkbenchSlice({
    required this.activeSessionId,
    required this.selectedMemberId,
    required this.sessionLaunchError,
  });

  factory ChatWorkbenchSlice.from(ChatState state) {
    return ChatWorkbenchSlice(
      activeSessionId: state.activeSessionId,
      selectedMemberId: state.selectedMemberId,
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
