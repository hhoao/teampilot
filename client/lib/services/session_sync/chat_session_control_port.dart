import '../../cubits/chat_cubit.dart';
import '../session_protocol/session_control_port.dart';

/// Routes session-plane cancel intents to the desktop's real runtime.
final class ChatSessionControlPort implements SessionControlPort {
  ChatSessionControlPort(this._chat);

  final ChatCubit _chat;

  @override
  Future<void> cancelTurn({
    required String sessionId,
    required String memberId,
  }) async {
    final tab = _chat.tabStore.getOpenTabBySessionId(sessionId);
    if (tab == null) return;
    final acp =
        tab.acpRuntimeForSeatMember(memberId) ??
        (tab.sessionId == memberId ? tab.acpRuntime : null);
    if (acp != null) {
      _chat.pauseFollowUpQueue(sessionId, memberId);
      acp.cancelTurn();
      return;
    }
    await _chat.interruptSelectedMemberTurn(
      sessionId: sessionId,
      memberId: memberId,
    );
  }
}
