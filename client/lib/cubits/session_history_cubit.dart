import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_session.dart';
import '../models/team_config.dart';
import '../services/cli/registry/capabilities/session_history_capability.dart';
import '../services/session/session_history_loader.dart';
import '../utils/logger.dart';

/// Host-local review history status — not session connect / "starting…".
enum SessionHistoryViewStatus { loading, ready, empty, error }

class SessionHistoryState extends Equatable {
  const SessionHistoryState({
    this.status = SessionHistoryViewStatus.empty,
    this.turns = const [],
    this.errorMessage,
    this.sessionId,
    this.memberId,
  });

  final SessionHistoryViewStatus status;
  final List<SessionHistoryTurn> turns;
  final String? errorMessage;
  final String? sessionId;
  final String? memberId;

  SessionHistoryState copyWith({
    SessionHistoryViewStatus? status,
    List<SessionHistoryTurn>? turns,
    String? errorMessage,
    bool clearError = false,
    String? sessionId,
    String? memberId,
  }) {
    return SessionHistoryState(
      status: status ?? this.status,
      turns: turns ?? this.turns,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      sessionId: sessionId ?? this.sessionId,
      memberId: memberId ?? this.memberId,
    );
  }

  @override
  List<Object?> get props => [
    status,
    turns,
    errorMessage,
    sessionId,
    memberId,
  ];
}

class SessionHistoryCubit extends Cubit<SessionHistoryState> {
  SessionHistoryCubit({required SessionHistoryLoader loader})
    : _loader = loader,
      super(const SessionHistoryState());

  final SessionHistoryLoader _loader;
  int _loadGeneration = 0;

  Future<void> load({
    required AppSession session,
    required String memberId,
    TeamProfile? team,
    String? workingDirectory,
    bool force = false,
  }) async {
    final gen = ++_loadGeneration;
    emit(
      SessionHistoryState(
        status: SessionHistoryViewStatus.loading,
        sessionId: session.sessionId,
        memberId: memberId,
      ),
    );

    try {
      final snapshot = await _loader.load(
        session: session,
        memberId: memberId,
        team: team,
        workingDirectory: workingDirectory,
        force: force,
      );
      if (gen != _loadGeneration || isClosed) return;
      emit(_stateFromSnapshot(snapshot, session.sessionId, memberId));
    } catch (e, st) {
      appLogger.e(
        '[session-history] cubit load failed session=${session.sessionId} '
        'member=$memberId team=${team?.id ?? session.sessionTeam}: $e',
        error: e,
        stackTrace: st,
      );
      if (gen != _loadGeneration || isClosed) return;
      emit(
        SessionHistoryState(
          status: SessionHistoryViewStatus.error,
          errorMessage: e.toString(),
          sessionId: session.sessionId,
          memberId: memberId,
        ),
      );
    }
  }

  void clear() {
    _loadGeneration++;
    emit(const SessionHistoryState());
  }

  static SessionHistoryState _stateFromSnapshot(
    SessionHistorySnapshot snapshot,
    String sessionId,
    String memberId,
  ) {
    switch (snapshot.status) {
      case SessionHistoryLoadStatus.ready:
        return SessionHistoryState(
          status: SessionHistoryViewStatus.ready,
          turns: snapshot.turns,
          sessionId: sessionId,
          memberId: memberId,
        );
      case SessionHistoryLoadStatus.empty:
        return SessionHistoryState(
          status: SessionHistoryViewStatus.empty,
          turns: snapshot.turns,
          sessionId: sessionId,
          memberId: memberId,
        );
      case SessionHistoryLoadStatus.error:
        return SessionHistoryState(
          status: SessionHistoryViewStatus.error,
          turns: snapshot.turns,
          errorMessage: snapshot.errorMessage,
          sessionId: sessionId,
          memberId: memberId,
        );
    }
  }
}
