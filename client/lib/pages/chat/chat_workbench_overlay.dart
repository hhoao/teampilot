import '../../cubits/chat/model/session_workbench_view.dart';

/// Which full-pane overlay sits above the (possibly offstage) terminal.
enum ChatWorkbenchOverlay {
  /// Remote CLI provision progress.
  remoteProvision,

  /// Chat surface — kept mounted during continue connect.
  chat,

  /// Full-screen session-starting spinner (Terminal / non-Chat connect).
  sessionStarting,

  /// No overlay; terminal (or empty) fills the pane.
  none,
}

/// Resolves the workbench center overlay.
///
/// When [workbenchView] is [SessionWorkbenchView.chat], Chat stays shown
/// even while [sessionConnectInProgress] is true so continue-from-Chat does
/// not dispose [SessionHistoryReview] mid-submit.
ChatWorkbenchOverlay resolveChatWorkbenchOverlay({
  required SessionWorkbenchView workbenchView,
  required bool sessionConnectInProgress,
  required bool showRemoteProvision,
}) {
  if (showRemoteProvision) return ChatWorkbenchOverlay.remoteProvision;
  if (workbenchView == SessionWorkbenchView.chat) {
    return ChatWorkbenchOverlay.chat;
  }
  if (sessionConnectInProgress) return ChatWorkbenchOverlay.sessionStarting;
  return ChatWorkbenchOverlay.none;
}
