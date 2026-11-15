import 'dart:async';

import '../../cubits/chat_cubit.dart';
import '../attention/attention_event.dart';
import '../chat/rewind/edit/seat_edit_coordinator.dart';
import '../session_protocol/session_authority.dart';
import '../session_protocol/session_models.dart';

/// Projects the local ChatCubit activity into the session authority.
///
/// Only open tabs are authority-owned sessions. Personal sessions use the
/// session id as their member id (the same convention as the shell/turn port).
final class ChatSessionActivitySource {
  ChatSessionActivitySource(this._chat);

  final ChatCubit _chat;
  StreamSubscription<ChatState>? _subscription;
  Set<String> _known = const {};
  final Map<String, bool> _wasReadyToChat = {};
  final Map<String, SeatEditCoordinator> _edits = {};
  final Map<String, void Function()> _editListeners = {};
  final Map<String, String> _lastEditKey = {};

  void start(SessionAuthority authority) {
    _subscription ??= _chat.stream.listen(
      (state) => _publish(state, authority),
    );
    _publish(_chat.state, authority);
  }

  void stop() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    for (final entry in _editListeners.entries) {
      _edits[entry.key]?.removeListener(entry.value);
    }
    _edits.clear();
    _editListeners.clear();
    _lastEditKey.clear();
    _known = const {};
    _wasReadyToChat.clear();
  }

  void dispose() => stop();

  void _publish(ChatState state, SessionAuthority authority) {
    final open = <String>{};
    for (final tab in _chat.tabStore.openTabs) {
      final sessionId = tab.sessionId.trim();
      if (sessionId.isEmpty) continue;
      open.add(sessionId);
      final activity = state.sessionActivities[sessionId];
      final selected = tab.selectedMemberId.trim();
      final memberIds = <String>{
        if (tab.memberShells.isEmpty && tab.memberAcpRuntimes.isEmpty)
          sessionId,
        ...tab.memberShells.keys,
        ...tab.memberAcpRuntimes.keys,
      };
      if (memberIds.isEmpty) {
        memberIds.add(selected.isEmpty ? sessionId : selected);
      }
      final seats = [
        for (final memberId in memberIds)
          SessionSeatActivity(
            sessionId: sessionId,
            memberId: memberId,
            state: _chat.isMemberWorking(sessionId, memberId)
                ? SessionSeatActivity.stateWorking
                : SessionSeatActivity.stateIdle,
            readyToChat:
                (activity?.isReadyToChat ?? false) &&
                (selected.isEmpty || selected == memberId),
            disposition: activity?.disposition.name ?? 'none',
          ),
      ];
      authority.updateSeats(
        sessionId,
        seats,
        workspaceId: tab.persistedSession?.workspaceId ?? '',
      );
      _bindSeatEdit(sessionId, authority);
      // Notification intent is session-level: one idle attention per completed
      // turn, independent of which seat the user currently has selected.
      //
      // Do not gate on `isMemberWorking` going false. ACP runtimes flip
      // `inTurn` before ChatCubit recomputes `sessionActivities`, so the
      // intermediate idle/none state clears a busy latch and the following
      // idle/completed state is missed. Seed instead: a session already ready
      // when the source starts is old state, not a fresh turn end.
      final readyToChat = activity?.isReadyToChat ?? false;
      final wasReadyToChat = _wasReadyToChat[sessionId];
      _wasReadyToChat[sessionId] = readyToChat;
      if (wasReadyToChat == false && readyToChat) {
        final seat = seats.firstWhere(
          (candidate) => candidate.readyToChat && !candidate.isBusy,
          orElse: () => seats.first,
        );
        unawaited(
          authority.publishAttention(
            sessionId: sessionId,
            kind: AttentionKind.idle,
            memberId: seat.memberId,
            turnId: seat.turnId,
            workspaceId: tab.persistedSession?.workspaceId ?? '',
          ),
        );
      }
    }
    for (final known in _known) {
      if (!open.contains(known)) {
        authority.removeSession(known);
        _wasReadyToChat.remove(known);
        _unbindSeatEdit(known);
      }
    }
    _known = open;
  }

  /// Mirrors one seat's edit transaction into the authority. The coordinator
  /// fires on every phase change, so the client sees progress, not just the
  /// final outcome.
  void _bindSeatEdit(String sessionId, SessionAuthority authority) {
    if (_edits.containsKey(sessionId)) return;
    final edit = _chat.seatEditFor(sessionId);
    void listener() => _publishSeatEdit(sessionId, edit, authority);
    _edits[sessionId] = edit;
    _editListeners[sessionId] = listener;
    edit.addListener(listener);
    _publishSeatEdit(sessionId, edit, authority);
  }

  void _unbindSeatEdit(String sessionId) {
    final listener = _editListeners.remove(sessionId);
    if (listener != null) _edits[sessionId]?.removeListener(listener);
    _edits.remove(sessionId);
    _lastEditKey.remove(sessionId);
  }

  void _publishSeatEdit(
    String sessionId,
    SeatEditCoordinator edit,
    SessionAuthority authority,
  ) {
    final op = edit.operation;
    if (op == null) return;
    final key = '${op.id}|${op.phase.name}|${op.failure?.name ?? ''}';
    if (_lastEditKey[sessionId] == key) return;
    _lastEditKey[sessionId] = key;
    authority.publishOperation(
      SessionOperation(
        id: op.id,
        kind: SessionOperation.kindTurnEdit,
        sessionId: op.sessionId,
        memberId: op.memberId,
        messageId: op.messageId,
        phase: op.phase.name,
        startedAt: op.startedAt.millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        errorCode: op.failure?.name ?? '',
      ),
    );
  }
}
