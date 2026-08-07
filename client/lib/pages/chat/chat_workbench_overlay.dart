import '../../cubits/ai_history_seat.dart';
import '../../cubits/chat/model/session_workbench_view.dart';
import '../../cubits/session/session_phase.dart';
import '../../cubits/session/workbench_overlay_resolver.dart';

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

/// Legacy shim for callers that still pass a bool connect flag. The single
/// source of truth is [resolveWorkbenchOverlay] (per-session, pure); this
/// adapts the old boolean to a pod phase for migration.
ChatWorkbenchOverlay resolveChatWorkbenchOverlay({
  required SessionWorkbenchView workbenchView,
  required bool sessionConnectInProgress,
  required bool showRemoteProvision,
}) {
  if (showRemoteProvision) return ChatWorkbenchOverlay.remoteProvision;
  return resolveWorkbenchOverlay(
    phase: sessionConnectInProgress
        ? SessionPhase.connecting
        : SessionPhase.running,
    historyStatus: AiHistoryViewStatus.ready,
    view: workbenchView,
  );
}

/// Whether the live terminal surface should stay in the workbench tree.
///
/// After a non-zero CLI exit, [sessionRunning] is false but [hasLaunchError]
/// keeps the Alacritty widget mounted so scrollback remains visible under the
/// error banner.
bool shouldMountWorkbenchTerminal({
  required bool sessionConnectInProgress,
  required bool sessionRunning,
  required bool showRemoteProvision,
  required bool hasLaunchError,
}) {
  return sessionConnectInProgress ||
      sessionRunning ||
      showRemoteProvision ||
      hasLaunchError;
}
