import 'dart:async';

import '../../cubits/chat_cubit.dart';
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
  final Map<String, bool> _wasBusy = {};
  int _attentionSeq = 0;

  void start(SessionAuthority authority) {
    _subscription ??= _chat.stream.listen(
      (state) => _publish(state, authority),
    );
    _publish(_chat.state, authority);
  }

  void stop() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _known = const {};
    _wasBusy.clear();
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
      for (final seat in seats) {
        final key = '${seat.sessionId}|${seat.memberId}';
        final wasBusy = _wasBusy[key] ?? false;
        if (wasBusy && !seat.isBusy && seat.readyToChat) {
          authority.publishAttention(
            sessionId: sessionId,
            kind: 'idle',
            id: 'attention-${++_attentionSeq}',
            memberId: seat.memberId,
            turnId: seat.turnId,
          );
        }
        _wasBusy[key] = seat.isBusy;
      }
    }
    for (final known in _known) {
      if (!open.contains(known)) {
        authority.removeSession(known);
        _wasBusy.removeWhere((key, _) => key.startsWith('$known|'));
      }
    }
    _known = open;
  }
}
