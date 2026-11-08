import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/session_protocol/session_models.dart';

/// Client-side projection of the session authority's pushed state.
class SessionRemoteActivityState extends Equatable {
  const SessionRemoteActivityState({this.sessions = const {}});

  final Map<String, SessionSnapshot> sessions;

  SessionSnapshot? session(String sessionId) => sessions[sessionId];

  bool isBusy(String sessionId) => sessions[sessionId]?.isBusy ?? false;

  bool isMemberBusy(String sessionId, String memberId) =>
      sessions[sessionId]?.seats.any(
        (seat) => seat.memberId == memberId && seat.isBusy,
      ) ??
      false;

  bool isReadyToChat(String sessionId) =>
      sessions[sessionId]?.seats.any((seat) => seat.readyToChat) ?? false;

  Set<String> get busySessionIds => {
    for (final entry in sessions.entries)
      if (entry.value.isBusy) entry.key,
  };

  SessionRemoteActivityState copyWith({
    Map<String, SessionSnapshot>? sessions,
  }) => SessionRemoteActivityState(sessions: sessions ?? this.sessions);

  @override
  List<Object?> get props => [sessions];
}

class SessionRemoteActivityCubit extends Cubit<SessionRemoteActivityState> {
  SessionRemoteActivityCubit() : super(const SessionRemoteActivityState());

  void applySnapshots(List<SessionSnapshot> snapshots) {
    emit(
      SessionRemoteActivityState(
        sessions: {
          for (final snapshot in snapshots) snapshot.sessionId: snapshot,
        },
      ),
    );
  }

  void applyDelta(SessionDelta delta) {
    if (isClosed) return;
    final sessions = Map<String, SessionSnapshot>.of(state.sessions);
    if (delta.removed) {
      sessions.remove(delta.sessionId);
    } else {
      final current = sessions[delta.sessionId];
      // A gap means a missed delta; ignore it and let the next snapshot/resync
      // repair the projection instead of applying an out-of-order change.
      if (current != null && delta.baseRevision != current.revision) return;
      sessions[delta.sessionId] = SessionSnapshot(
        sessionId: delta.sessionId,
        epoch: delta.epoch,
        revision: delta.revision,
        seats: delta.seats,
        authorityId: current?.authorityId ?? '',
        workspaceId: delta.workspaceId.isNotEmpty
            ? delta.workspaceId
            : (current?.workspaceId ?? ''),
      );
    }
    emit(state.copyWith(sessions: sessions));
  }

  void clear() {
    if (state.sessions.isEmpty) return;
    emit(const SessionRemoteActivityState());
  }
}
