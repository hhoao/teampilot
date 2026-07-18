import 'dart:math' as math;

import 'package:ai_message_core/ai_message_core.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../models/app_session.dart';
import '../models/team_config.dart';
import '../services/session/ai_history_loader.dart';
import '../services/session/ai_history_pending_text.dart';
import '../services/session/session_history_pagination.dart';
import '../utils/logging/logger.dart';

/// Host-local AI history status — not session connect / "starting…".
enum AiHistoryViewStatus { loading, ready, empty, error }

class AiHistoryState extends Equatable {
  const AiHistoryState({
    this.status = AiHistoryViewStatus.empty,
    this.totalMessageCount = 0,
    this.hasOlder = false,
    this.isLoadingOlder = false,
    this.errorMessage,
    this.softReloadError,
    this.sessionId,
    this.memberId,
  });

  final AiHistoryViewStatus status;
  final int totalMessageCount;
  final bool hasOlder;
  final bool isLoadingOlder;
  final String? errorMessage;
  final String? softReloadError;
  final String? sessionId;
  final String? memberId;

  AiHistoryState copyWith({
    AiHistoryViewStatus? status,
    int? totalMessageCount,
    bool? hasOlder,
    bool? isLoadingOlder,
    String? errorMessage,
    bool clearError = false,
    String? softReloadError,
    bool clearSoftReloadError = false,
    String? sessionId,
    String? memberId,
  }) {
    return AiHistoryState(
      status: status ?? this.status,
      totalMessageCount: totalMessageCount ?? this.totalMessageCount,
      hasOlder: hasOlder ?? this.hasOlder,
      isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      softReloadError: clearSoftReloadError
          ? null
          : (softReloadError ?? this.softReloadError),
      sessionId: sessionId ?? this.sessionId,
      memberId: memberId ?? this.memberId,
    );
  }

  @override
  List<Object?> get props => [
    status,
    totalMessageCount,
    hasOlder,
    isLoadingOlder,
    errorMessage,
    softReloadError,
    sessionId,
    memberId,
  ];
}

class _PendingUser {
  const _PendingUser({required this.id, required this.text});

  final String id;
  final String text;
}

class AiHistoryCubit extends Cubit<AiHistoryState> {
  AiHistoryCubit({required AiHistoryLoader loader})
    : _loader = loader,
      super(const AiHistoryState());

  static const _uuid = Uuid();

  final AiHistoryLoader _loader;
  final ExternalStoreAiThreadRuntime runtime = ExternalStoreAiThreadRuntime();

  int _loadGeneration = 0;
  List<AiMessage> _allMessages = const [];
  int _visibleCount = 0;
  final List<_PendingUser> _pendingQueue = [];

  AppSession? _lastSession;
  String? _lastMemberId;
  TeamProfile? _lastTeam;
  String? _lastWorkingDirectory;

  Future<void> load({
    required AppSession session,
    required String memberId,
    TeamProfile? team,
    String? workingDirectory,
    bool force = false,
  }) async {
    final seatChanged =
        state.sessionId != session.sessionId || state.memberId != memberId;
    if (seatChanged) {
      clearPendings();
    }

    _lastSession = session;
    _lastMemberId = memberId;
    _lastTeam = team;
    _lastWorkingDirectory = workingDirectory;

    final gen = ++_loadGeneration;
    _allMessages = const [];
    _visibleCount = 0;
    runtime.setLoading();
    emit(
      AiHistoryState(
        status: AiHistoryViewStatus.loading,
        sessionId: session.sessionId,
        memberId: memberId,
      ),
    );

    try {
      final messages = await _loader.load(
        session: session,
        memberId: memberId,
        team: team,
        workingDirectory: workingDirectory,
        force: force,
      );
      if (gen != _loadGeneration || isClosed) return;
      _applyMessages(messages, session.sessionId, memberId);
    } catch (e, st) {
      appLogger.e(
        '[ai-history] cubit load failed session=${session.sessionId} '
        'member=$memberId team=${team?.id ?? session.sessionTeam}: $e',
        error: e,
        stackTrace: st,
      );
      if (gen != _loadGeneration || isClosed) return;
      _allMessages = const [];
      _visibleCount = 0;
      runtime.setError(e.toString());
      emit(
        AiHistoryState(
          status: AiHistoryViewStatus.error,
          errorMessage: e.toString(),
          sessionId: session.sessionId,
          memberId: memberId,
        ),
      );
    }
  }

  /// Live refresh: tip-Δ window, no loading flash when already ready.
  Future<void> softReload() async {
    final session = _lastSession;
    final memberId = _lastMemberId;
    if (session == null || memberId == null) return;

    final gen = _loadGeneration;
    final sessionId = session.sessionId;

    try {
      _loader.invalidate(sessionId: sessionId, memberId: memberId);
      final messages = await _loader.load(
        session: session,
        memberId: memberId,
        team: _lastTeam,
        workingDirectory: _lastWorkingDirectory,
        force: true,
      );
      if (gen != _loadGeneration || isClosed) return;
      if (session.sessionId != (_lastSession?.sessionId ?? '') ||
          memberId != _lastMemberId) {
        return;
      }
      // Pre-locate: empty parse keeps prior messages until a transcript exists.
      if (messages.isEmpty && _allMessages.isNotEmpty) return;
      _applySoftReloadMessages(messages, sessionId, memberId);
    } catch (e, st) {
      appLogger.e(
        '[ai-history] cubit softReload failed session=$sessionId '
        'member=$memberId: $e',
        error: e,
        stackTrace: st,
      );
      if (gen != _loadGeneration || isClosed) return;
      emit(state.copyWith(softReloadError: e.toString()));
    }
  }

  /// Review remount: soft when already ready for this seat, else cold load.
  Future<void> softReloadOrLoad({
    required AppSession session,
    required String memberId,
    TeamProfile? team,
    String? workingDirectory,
  }) async {
    if (state.status == AiHistoryViewStatus.ready &&
        state.sessionId == session.sessionId &&
        state.memberId == memberId) {
      await softReload();
      return;
    }
    await load(
      session: session,
      memberId: memberId,
      team: team,
      workingDirectory: workingDirectory,
    );
  }

  /// Stale hook from ChatCubit: soft when ready for [sessionId].
  Future<void> softReloadIfSession(String sessionId) async {
    if (state.status == AiHistoryViewStatus.ready &&
        state.sessionId == sessionId) {
      await softReload();
      return;
    }
    await invalidateAndReload(sessionId);
  }

  void enqueuePendingUser(String text) {
    final pending = _PendingUser(id: 'pending:${_uuid.v4()}', text: text);
    _pendingQueue.add(pending);
    _remergePendingsOntoRuntime();
  }

  void clearPendings() {
    if (_pendingQueue.isEmpty) return;
    _pendingQueue.clear();
    if (state.status == AiHistoryViewStatus.ready ||
        state.status == AiHistoryViewStatus.empty) {
      _remergePendingsOntoRuntime();
    }
  }

  /// Drop cache for [sessionId] and force-reload if this cubit last loaded it.
  Future<void> invalidateAndReload(String sessionId) async {
    _loader.invalidate(sessionId: sessionId);
    final session = _lastSession;
    final memberId = _lastMemberId;
    if (session == null || memberId == null) return;
    if (session.sessionId != sessionId) return;
    await load(
      session: session,
      memberId: memberId,
      team: _lastTeam,
      workingDirectory: _lastWorkingDirectory,
      force: true,
    );
  }

  void invalidateSession(String sessionId) {
    _loader.invalidate(sessionId: sessionId);
  }

  void loadOlder() {
    if (state.status != AiHistoryViewStatus.ready) return;
    if (!state.hasOlder || state.isLoadingOlder) return;

    emit(state.copyWith(isLoadingOlder: true));
    _visibleCount = math.min(
      _visibleCount + kSessionHistoryOlderPageSize,
      _allMessages.length,
    );
    _emitReadyWindow(state.sessionId, state.memberId);
  }

  void clear() {
    _loadGeneration++;
    _allMessages = const [];
    _visibleCount = 0;
    _pendingQueue.clear();
    _lastSession = null;
    _lastMemberId = null;
    _lastTeam = null;
    _lastWorkingDirectory = null;
    runtime.setEmpty();
    emit(const AiHistoryState());
  }

  void _applyMessages(
    List<AiMessage> messages,
    String sessionId,
    String memberId,
  ) {
    _allMessages = messages;
    _visibleCount = math.min(kSessionHistoryInitialTurns, _allMessages.length);
    _dropMatchedPendings();

    if (_allMessages.isEmpty) {
      runtime.setEmpty();
      emit(
        AiHistoryState(
          status: AiHistoryViewStatus.empty,
          sessionId: sessionId,
          memberId: memberId,
        ),
      );
      _remergePendingsOntoRuntime();
      return;
    }

    _emitReadyWindow(sessionId, memberId);
    _remergePendingsOntoRuntime();
  }

  void _applySoftReloadMessages(
    List<AiMessage> messages,
    String sessionId,
    String memberId,
  ) {
    final oldLength = _allMessages.length;
    final oldVisible = _visibleCount;
    final newLength = messages.length;
    _allMessages = messages;
    final tipDelta = math.max(0, newLength - oldLength);
    if (newLength < oldLength) {
      _visibleCount = math.min(oldVisible, newLength);
    } else {
      _visibleCount = math.min(newLength, oldVisible + tipDelta);
    }
    _dropMatchedPendings();

    if (_allMessages.isEmpty) {
      runtime.setEmpty();
      emit(
        AiHistoryState(
          status: AiHistoryViewStatus.empty,
          sessionId: sessionId,
          memberId: memberId,
        ),
      );
      _remergePendingsOntoRuntime();
      return;
    }

    _emitReadyWindow(sessionId, memberId);
    _remergePendingsOntoRuntime();
  }

  void _dropMatchedPendings() {
    if (_pendingQueue.isEmpty) return;
    final n = math.max(_pendingQueue.length + 2, 5);
    final userTurns = [
      for (final m in _allMessages)
        if (m.role == AiRole.user) m,
    ];
    final tipUsers = userTurns.length <= n
        ? userTurns
        : userTurns.sublist(userTurns.length - n);
    final matched = List<bool>.filled(tipUsers.length, false);
    final remaining = <_PendingUser>[];

    for (final pending in _pendingQueue) {
      final norm = normalizeAiHistoryPendingText(pending.text);
      var matchIdx = -1;
      for (var i = tipUsers.length - 1; i >= 0; i--) {
        if (matched[i]) continue;
        final tipNorm = normalizeAiHistoryPendingText(
          aiHistoryUserPlainText(tipUsers[i]),
        );
        if (tipNorm == norm) {
          matchIdx = i;
          break;
        }
      }
      if (matchIdx >= 0) {
        matched[matchIdx] = true;
      } else {
        remaining.add(pending);
      }
    }
    _pendingQueue
      ..clear()
      ..addAll(remaining);
  }

  void _remergePendingsOntoRuntime() {
    if (_pendingQueue.isEmpty) {
      if (state.status == AiHistoryViewStatus.ready) {
        runtime.setMessages(_visibleSlice());
      } else if (_allMessages.isEmpty &&
          state.status == AiHistoryViewStatus.empty) {
        runtime.setEmpty();
      }
      return;
    }
    final slice = _visibleSlice();
    final pendingMessages = [
      for (final p in _pendingQueue)
        AiMessage(
          id: p.id,
          role: AiRole.user,
          parts: [AiTextPart(text: p.text)],
        ),
    ];
    runtime.setMessages([...slice, ...pendingMessages]);
  }

  void _emitReadyWindow(String? sessionId, String? memberId) {
    final slice = _visibleSlice();
    runtime.setMessages(slice);
    emit(
      AiHistoryState(
        status: AiHistoryViewStatus.ready,
        totalMessageCount: _allMessages.length,
        hasOlder: _hasOlder(),
        isLoadingOlder: false,
        sessionId: sessionId,
        memberId: memberId,
      ),
    );
  }

  List<AiMessage> _visibleSlice() {
    if (_allMessages.isEmpty) return const [];
    final start = math.max(0, _allMessages.length - _visibleCount);
    return _allMessages.sublist(start);
  }

  bool _hasOlder() => _visibleCount < _allMessages.length;

  @override
  Future<void> close() {
    runtime.close();
    return super.close();
  }
}
