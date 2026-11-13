import '../../cubits/chat_cubit.dart';
import '../../models/session_list_entry.dart';
import '../session_protocol/session_control_port.dart';

/// Routes session-plane cancel intents to the desktop's real runtime.
final class ChatSessionControlPort implements SessionControlPort {
  ChatSessionControlPort(this._chat);

  final ChatCubit _chat;

  @override
  Future<void> adoptSession({
    required String workspaceId,
    required Map<String, Object?> entry,
  }) async {
    final id = workspaceId.trim();
    final sessionId = entry['sessionId'];
    if (id.isEmpty || sessionId is! String || sessionId.trim().isEmpty) {
      return;
    }
    if (!_chat.state.workspaces.any(
      (workspace) => workspace.workspaceId == id,
    )) {
      // The session may belong to a workspace created on another device.
      await _chat.refreshWorkspaceFromHome(id);
    }
    final session = SessionListEntry.fromJson(entry).toListSession(id);
    _chat.adoptRemoteSession(session);
  }

  @override
  Future<void> removeSession({
    required String workspaceId,
    required String sessionId,
  }) async {
    final sid = sessionId.trim();
    final wid = workspaceId.trim();
    if (sid.isEmpty) return;
    if (wid.isNotEmpty) {
      final existing = _chat.state.sessions
          .where((session) => session.sessionId == sid)
          .firstOrNull;
      if (existing != null && existing.workspaceId != wid) return;
    }
    _chat.removeSessionSnapshot(sid);
  }

  @override
  Future<void> refreshWorkspaceSessions(String workspaceId) async {
    final id = workspaceId.trim();
    if (id.isEmpty) return;
    await _chat.refreshWorkspaceFromHome(id);
  }

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

  @override
  Future<void> editTurn({
    required String sessionId,
    required String memberId,
    required String operationId,
    required String userMessageId,
    required String text,
  }) async {
    final accepted = await _chat
        .seatEditFor(sessionId)
        .submit(
          messageId: userMessageId,
          memberId: memberId,
          text: text,
          operationId: operationId,
        );
    if (!accepted) {
      // The intent result must reflect a refused edit; the authority turns a
      // thrown control error into `rejected: control_failed`.
      throw StateError('edit was not accepted');
    }
  }

  @override
  Future<void> cancelEdit({
    required String sessionId,
    required String memberId,
    required String operationId,
  }) async {
    final edit = _chat.seatEditFor(sessionId);
    if (edit.operation?.id != operationId) return;
    edit.cancel();
  }
}
