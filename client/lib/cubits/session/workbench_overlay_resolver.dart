import '../../cubits/ai_history_seat.dart';
import '../../pages/chat/chat_workbench_overlay.dart';
import '../chat/model/session_workbench_view.dart';
import 'session_phase.dart';

/// Overlay for ONE session, as a pure function of that session's own state.
///
/// Explicitly never reads another session's phase or a global connecting id —
/// this is what guarantees a session that is launching cannot color a
/// different conversation's overlay.
ChatWorkbenchOverlay resolveWorkbenchOverlay({
  required SessionPhase phase,
  required AiHistoryViewStatus historyStatus,
  required SessionWorkbenchView view,
}) {
  if (view == SessionWorkbenchView.chat) return ChatWorkbenchOverlay.chat;
  if (phase == SessionPhase.connecting ||
      phase == SessionPhase.provisioning) {
    return ChatWorkbenchOverlay.sessionStarting;
  }
  return ChatWorkbenchOverlay.none;
}
