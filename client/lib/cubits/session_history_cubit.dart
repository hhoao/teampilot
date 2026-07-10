import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_session.dart';
import '../models/team_config.dart';
import '../services/cli/registry/capabilities/session_history_capability.dart';
import '../services/session/session_history_loader.dart';
import '../services/session/session_history_pagination.dart';
import '../utils/logger.dart';

/// Host-local review history status — not session connect / "starting…".
enum SessionHistoryViewStatus { loading, ready, empty, error }

class SessionHistoryState extends Equatable {
  const SessionHistoryState({
    this.status = SessionHistoryViewStatus.empty,
    this.turns = const [],
    this.totalTurnCount = 0,
    this.hasOlder = false,
    this.isLoadingOlder = false,
    this.errorMessage,
    this.sessionId,
    this.memberId,
  });

  final SessionHistoryViewStatus status;
  /// Chronological slice of turns currently visible in the list.
  final List<SessionHistoryTurn> turns;
  final int totalTurnCount;
  final bool hasOlder;
  final bool isLoadingOlder;
  final String? errorMessage;
  final String? sessionId;
  final String? memberId;

  SessionHistoryState copyWith({
    SessionHistoryViewStatus? status,
    List<SessionHistoryTurn>? turns,
    int? totalTurnCount,
    bool? hasOlder,
    bool? isLoadingOlder,
    String? errorMessage,
    bool clearError = false,
    String? sessionId,
    String? memberId,
  }) {
    return SessionHistoryState(
      status: status ?? this.status,
      turns: turns ?? this.turns,
      totalTurnCount: totalTurnCount ?? this.totalTurnCount,
      hasOlder: hasOlder ?? this.hasOlder,
      isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      sessionId: sessionId ?? this.sessionId,
      memberId: memberId ?? this.memberId,
    );
  }

  @override
  List<Object?> get props => [
    status,
    turns,
    totalTurnCount,
    hasOlder,
    isLoadingOlder,
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
  List<SessionHistoryTurn> _allTurns = const [];
  int _visibleCount = 0;

  Future<void> load({
    required AppSession session,
    required String memberId,
    TeamProfile? team,
    String? workingDirectory,
    bool force = false,
  }) async {
    final gen = ++_loadGeneration;
    _allTurns = const [];
    _visibleCount = 0;
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
      _allTurns = const [];
      _visibleCount = 0;
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

  void loadOlder() {
    if (state.status != SessionHistoryViewStatus.ready) return;
    if (!state.hasOlder || state.isLoadingOlder) return;

    emit(state.copyWith(isLoadingOlder: true));
    _visibleCount = math.min(
      _visibleCount + kSessionHistoryOlderPageSize,
      _allTurns.length,
    );
    emit(_readyStateFromWindow(state.sessionId, state.memberId));
  }

  void clear() {
    _loadGeneration++;
    _allTurns = const [];
    _visibleCount = 0;
    emit(const SessionHistoryState());
  }

  SessionHistoryState _stateFromSnapshot(
    SessionHistorySnapshot snapshot,
    String sessionId,
    String memberId,
  ) {
    _allTurns = snapshot.turns;
    _visibleCount = math.min(kSessionHistoryInitialTurns, _allTurns.length);

    switch (snapshot.status) {
      case SessionHistoryLoadStatus.ready:
        return _readyStateFromWindow(sessionId, memberId);
      case SessionHistoryLoadStatus.empty:
        return SessionHistoryState(
          status: SessionHistoryViewStatus.empty,
          sessionId: sessionId,
          memberId: memberId,
        );
      case SessionHistoryLoadStatus.error:
        return SessionHistoryState(
          status: SessionHistoryViewStatus.error,
          turns: _visibleSlice(),
          totalTurnCount: _allTurns.length,
          hasOlder: _hasOlder(),
          errorMessage: snapshot.errorMessage,
          sessionId: sessionId,
          memberId: memberId,
        );
    }
  }

  SessionHistoryState _readyStateFromWindow(
    String? sessionId,
    String? memberId,
  ) {
    return SessionHistoryState(
      status: SessionHistoryViewStatus.ready,
      turns: _visibleSlice(),
      totalTurnCount: _allTurns.length,
      hasOlder: _hasOlder(),
      isLoadingOlder: false,
      sessionId: sessionId,
      memberId: memberId,
    );
  }

  List<SessionHistoryTurn> _visibleSlice() {
    if (_allTurns.isEmpty) return const [];
    final start = math.max(0, _allTurns.length - _visibleCount);
    return _allTurns.sublist(start);
  }

  bool _hasOlder() => _visibleCount < _allTurns.length;
}
