import 'package:flutter/foundation.dart';

import '../chat/model/session_workbench_view.dart';
import 'session_phase.dart';

/// Immutable projection of a session pod's observable state. Selectors bind to
/// [revision] so unchanged pods do not rebuild.
@immutable
class SessionPodState {
  const SessionPodState({
    required this.sessionId,
    required this.workspaceId,
    this.phase = SessionPhase.idle,
    this.launchError,
    this.selectedMemberId = '',
    this.view = SessionWorkbenchView.chat,
    this.revision = 0,
  });

  final String sessionId;
  final String workspaceId;
  final SessionPhase phase;
  final String? launchError;
  final String selectedMemberId;
  final SessionWorkbenchView view;

  /// Bumped on every field change so selectors can cheaply skip rebuilds.
  final int revision;

  SessionPodState copyWith({
    SessionPhase? phase,
    String? launchError,
    bool clearLaunchError = false,
    String? selectedMemberId,
    SessionWorkbenchView? view,
  }) {
    final nextPhase = phase ?? this.phase;
    final nextError =
        clearLaunchError ? null : (launchError ?? this.launchError);
    final nextMember = selectedMemberId ?? this.selectedMemberId;
    final nextView = view ?? this.view;
    final changed = nextPhase != this.phase ||
        nextError != this.launchError ||
        nextMember != this.selectedMemberId ||
        nextView != this.view;
    return SessionPodState(
      sessionId: sessionId,
      workspaceId: workspaceId,
      phase: nextPhase,
      launchError: nextError,
      selectedMemberId: nextMember,
      view: nextView,
      revision: changed ? revision + 1 : revision,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SessionPodState &&
      other.sessionId == sessionId &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(sessionId, revision);
}

/// Mutable runtime object for ONE open conversation. Owns the pod's observable
/// state and (Phase 2) its HistoryStore. Pure-Dart; the host (ChatCubit) is
/// notified through [onChanged] so it can emit stateVersion bumps.
class SessionPod {
  SessionPod({
    required this.sessionId,
    required this.workspaceId,
    this.onChanged,
    SessionPodState? initial,
  }) : _state = initial ??
            SessionPodState(sessionId: sessionId, workspaceId: workspaceId);

  final String sessionId;
  final String workspaceId;
  final void Function()? onChanged;

  SessionPodState _state;
  SessionPodState get state => _state;

  void setPhase(SessionPhase phase) {
    if (_state.phase == phase) return;
    _state = _state.copyWith(phase: phase);
    onChanged?.call();
  }

  void setLaunchError(String? error) {
    final next = error == null
        ? _state.copyWith(clearLaunchError: true)
        : _state.copyWith(launchError: error);
    if (next == _state) return;
    _state = next;
    onChanged?.call();
  }

  void selectMember(String memberId) {
    if (_state.selectedMemberId == memberId) return;
    _state = _state.copyWith(selectedMemberId: memberId);
    onChanged?.call();
  }

  void setView(SessionWorkbenchView view) {
    if (_state.view == view) return;
    _state = _state.copyWith(view: view);
    onChanged?.call();
  }
}
