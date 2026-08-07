import 'package:flutter/foundation.dart';

import '../chat/model/session_workbench_view.dart';
import 'session_phase.dart';

/// Immutable per-session state value. The runtime pod (Task 5) owns a mutable
/// copy of this plus the HistoryStore/keep-alive identity; the UI binds to
/// revisions of this value so unchanged pods do not rebuild.
@immutable
class SessionPod {
  const SessionPod({
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

  SessionPod copyWith({
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
    return SessionPod(
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
      other is SessionPod &&
      other.sessionId == sessionId &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(sessionId, revision);
}
