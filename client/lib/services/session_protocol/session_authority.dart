import 'dart:async';
import 'dart:convert';

import '../../utils/logging/logger.dart';
import 'session_control_port.dart';
import 'session_models.dart';

/// One session's authoritative state on the process that owns its runtime.
///
/// The authority is deliberately a pure in-memory reducer: the app shell feeds
/// it session activity, and it emits ordered snapshots/deltas plus typed intent
/// results. It never touches PTYs directly; control goes through
/// [SessionControlPort].
final class SessionAuthority {
  SessionAuthority({
    required this.authorityId,
    required SessionControlPort controlPort,
    int? epoch,
    DateTime Function()? clock,
  }) : _controlPort = controlPort,
       epoch = epoch ?? DateTime.now().millisecondsSinceEpoch,
       _clock = clock ?? DateTime.now;

  final String authorityId;
  final int epoch;
  final SessionControlPort _controlPort;
  final DateTime Function() _clock;

  final Map<String, Map<String, SessionSeatActivity>> _sessions = {};
  final Map<String, int> _revisions = {};
  final Map<String, String> _workspaceIds = {};
  final Map<String, int> _contentSeq = {};
  final Map<String, int> _contentDeltaSeq = {};
  final Map<String, int> _sessionListRevisions = {};

  final StreamController<SessionDelta> _deltas =
      StreamController<SessionDelta>.broadcast();
  final StreamController<SessionContentInvalidated> _content =
      StreamController<SessionContentInvalidated>.broadcast();
  final StreamController<SessionContentDelta> _contentDeltas =
      StreamController<SessionContentDelta>.broadcast();
  final StreamController<SessionListDelta> _sessionLists =
      StreamController<SessionListDelta>.broadcast();
  final StreamController<SessionAttention> _attention =
      StreamController<SessionAttention>.broadcast();

  Stream<SessionDelta> get deltas => _deltas.stream;
  Stream<SessionContentInvalidated> get content => _content.stream;
  Stream<SessionContentDelta> get contentDeltas => _contentDeltas.stream;
  Stream<SessionListDelta> get sessionLists => _sessionLists.stream;
  Stream<SessionAttention> get attention => _attention.stream;

  List<SessionSnapshot> snapshots() {
    final ids = _sessions.keys.toList()..sort();
    return [
      for (final id in ids)
        if (snapshot(id) case final snapshot?) snapshot,
    ];
  }

  SessionSnapshot? snapshot(String sessionId) {
    final seats = _sessions[sessionId];
    if (seats == null) return null;
    final ordered = seats.values.toList()
      ..sort((a, b) => a.memberId.compareTo(b.memberId));
    return SessionSnapshot(
      sessionId: sessionId,
      epoch: epoch,
      revision: _revisions[sessionId] ?? 0,
      seats: ordered,
      authorityId: authorityId,
      workspaceId: _workspaceIds[sessionId] ?? '',
    );
  }

  /// Replaces one session's seat set. No-op when the normalized value is
  /// unchanged, so a per-second activity recompute does not spam the wire.
  SessionDelta? updateSeats(
    String sessionId,
    Iterable<SessionSeatActivity> seats, {
    String workspaceId = '',
  }) {
    final trimmed = sessionId.trim();
    if (trimmed.isEmpty) return null;
    final normalizedWorkspace = workspaceId.trim();
    final previousWorkspace = _workspaceIds[trimmed] ?? '';
    if (normalizedWorkspace.isNotEmpty) {
      _workspaceIds[trimmed] = normalizedWorkspace;
    }
    final normalized = _normalize(trimmed, seats);
    final previous = _sessions[trimmed];
    final previousKey = previous == null ? '' : _key(previous.values);
    if (normalized.isEmpty) {
      return previous == null ? null : removeSession(trimmed);
    }
    final nextKey = _key(normalized.values);
    final workspaceChanged =
        normalizedWorkspace.isNotEmpty &&
        previousWorkspace != normalizedWorkspace;
    if (previousKey == nextKey && !workspaceChanged) return null;
    final base = _revisions[trimmed] ?? 0;
    final revision = base + 1;
    _sessions[trimmed] = normalized;
    _revisions[trimmed] = revision;
    final delta = SessionDelta(
      sessionId: trimmed,
      epoch: epoch,
      baseRevision: base,
      revision: revision,
      seats: normalized.values.toList()
        ..sort((a, b) => a.memberId.compareTo(b.memberId)),
      workspaceId: _workspaceIds[trimmed] ?? '',
    );
    if (!_deltas.isClosed) _deltas.add(delta);
    return delta;
  }

  /// Drops every session without disposing the streams. Used when the home
  /// role leaves the authority (local -> ssh) so a later restart does not
  /// advertise stale sessions.
  void clear() {
    for (final sessionId in _sessions.keys.toList()) {
      removeSession(sessionId);
    }
    _workspaceIds.clear();
    _contentSeq.clear();
    _contentDeltaSeq.clear();
    _sessionListRevisions.clear();
  }

  SessionDelta? removeSession(String sessionId) {
    final trimmed = sessionId.trim();
    final previous = _sessions.remove(trimmed);
    if (previous == null) return null;
    final workspaceId = _workspaceIds.remove(trimmed) ?? '';
    _contentDeltaSeq.removeWhere((key, _) => key.startsWith('$trimmed|'));
    _contentSeq.remove(trimmed);
    final base = _revisions[trimmed] ?? 0;
    final revision = base + 1;
    _revisions[trimmed] = revision;
    final delta = SessionDelta(
      sessionId: trimmed,
      epoch: epoch,
      baseRevision: base,
      revision: revision,
      seats: const [],
      removed: true,
      workspaceId: workspaceId,
    );
    if (!_deltas.isClosed) _deltas.add(delta);
    return delta;
  }

  Future<SessionIntentResult> handleIntent(SessionIntent intent) async {
    final deadline = intent.deadline;
    if (deadline != null && _clock().toUtc().isAfter(deadline.toUtc())) {
      return SessionIntentResult(
        id: intent.id,
        status: SessionIntentStatus.expired,
        epoch: epoch,
        revision: _revisions[intent.sessionId] ?? 0,
        code: 'deadline_exceeded',
      );
    }
    final expected = intent.expectedEpoch;
    if (expected != null && expected != epoch) {
      return SessionIntentResult(
        id: intent.id,
        status: SessionIntentStatus.rejected,
        epoch: epoch,
        revision: _revisions[intent.sessionId] ?? 0,
        code: 'authority_moved',
      );
    }
    if (intent.op == 'session.refresh') {
      final workspaceId = intent.workspaceId.trim();
      if (workspaceId.isEmpty) {
        return SessionIntentResult(
          id: intent.id,
          status: SessionIntentStatus.rejected,
          epoch: epoch,
          code: 'workspace_required',
        );
      }
      try {
        await _controlPort.refreshWorkspaceSessions(workspaceId);
        return SessionIntentResult(
          id: intent.id,
          status: SessionIntentStatus.applied,
          epoch: epoch,
          revision: _revisions[intent.sessionId] ?? 0,
        );
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[session-authority] refresh failed workspace=$workspaceId',
          error: error,
          stackTrace: stackTrace,
        );
        return SessionIntentResult(
          id: intent.id,
          status: SessionIntentStatus.rejected,
          epoch: epoch,
          code: 'control_failed',
          message: '$error',
        );
      }
    }
    if (intent.op == 'session.create') {
      final workspaceId = intent.workspaceId.trim();
      final entry = intent.sessionListEntry;
      if (workspaceId.isEmpty || entry == null) {
        return SessionIntentResult(
          id: intent.id,
          status: SessionIntentStatus.rejected,
          epoch: epoch,
          code: 'session_row_required',
        );
      }
      try {
        await _controlPort.adoptSession(workspaceId: workspaceId, entry: entry);
        final delta = publishSessionList(
          workspaceId: workspaceId,
          upserted: [entry],
        );
        return SessionIntentResult(
          id: intent.id,
          status: SessionIntentStatus.applied,
          epoch: epoch,
          revision: delta.revision,
        );
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[session-authority] session.create failed workspace=$workspaceId',
          error: error,
          stackTrace: stackTrace,
        );
        return SessionIntentResult(
          id: intent.id,
          status: SessionIntentStatus.rejected,
          epoch: epoch,
          code: 'control_failed',
          message: '$error',
        );
      }
    }
    if (intent.op == 'session.remove') {
      final workspaceId = intent.workspaceId.trim();
      final sessionId = intent.sessionId.trim();
      if (workspaceId.isEmpty || sessionId.isEmpty) {
        return SessionIntentResult(
          id: intent.id,
          status: SessionIntentStatus.rejected,
          epoch: epoch,
          code: 'session_row_required',
        );
      }
      try {
        await _controlPort.removeSession(
          workspaceId: workspaceId,
          sessionId: sessionId,
        );
        final delta = publishSessionList(
          workspaceId: workspaceId,
          removed: [sessionId],
        );
        return SessionIntentResult(
          id: intent.id,
          status: SessionIntentStatus.applied,
          epoch: epoch,
          revision: delta.revision,
        );
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[session-authority] session.remove failed workspace=$workspaceId '
          'session=$sessionId',
          error: error,
          stackTrace: stackTrace,
        );
        return SessionIntentResult(
          id: intent.id,
          status: SessionIntentStatus.rejected,
          epoch: epoch,
          code: 'control_failed',
          message: '$error',
        );
      }
    }
    final session = snapshot(intent.sessionId);
    if (session == null) {
      return SessionIntentResult(
        id: intent.id,
        status: SessionIntentStatus.noop,
        epoch: epoch,
        code: 'session_not_running',
      );
    }
    switch (intent.op) {
      case 'turn.cancel':
        final memberId = intent.memberId.trim();
        SessionSeatActivity? target;
        for (final seat in session.seats) {
          if (seat.memberId == memberId) {
            target = seat;
            break;
          }
        }
        if (target == null || !target.isBusy) {
          return SessionIntentResult(
            id: intent.id,
            status: SessionIntentStatus.noop,
            epoch: epoch,
            revision: session.revision,
            code: 'turn_already_ended',
          );
        }
        try {
          await _controlPort.cancelTurn(
            sessionId: intent.sessionId,
            memberId: memberId,
          );
          return SessionIntentResult(
            id: intent.id,
            status: SessionIntentStatus.applied,
            epoch: epoch,
            revision: _revisions[intent.sessionId] ?? session.revision,
          );
        } on Object catch (error, stackTrace) {
          appLogger.w(
            '[session-authority] cancel failed session=${intent.sessionId} '
            'member=$memberId',
            error: error,
            stackTrace: stackTrace,
          );
          return SessionIntentResult(
            id: intent.id,
            status: SessionIntentStatus.rejected,
            epoch: epoch,
            revision: session.revision,
            code: 'control_failed',
            message: '$error',
          );
        }
      default:
        return SessionIntentResult(
          id: intent.id,
          status: SessionIntentStatus.rejected,
          epoch: epoch,
          revision: session.revision,
          code: 'unsupported_op',
        );
    }
  }

  SessionContentInvalidated publishContentInvalidated({
    required String sessionId,
    String memberId = '',
    String kind = 'transcript',
  }) {
    final trimmed = sessionId.trim();
    final seq = (_contentSeq[trimmed] ?? 0) + 1;
    _contentSeq[trimmed] = seq;
    final event = SessionContentInvalidated(
      sessionId: trimmed,
      seq: seq,
      memberId: memberId,
      kind: kind,
    );
    if (!_content.isClosed) _content.add(event);
    return event;
  }

  /// Publishes a session-list delta for one workspace.
  SessionListDelta publishSessionList({
    required String workspaceId,
    List<Map<String, Object?>> upserted = const [],
    List<String> removed = const [],
  }) {
    final trimmed = workspaceId.trim();
    final revision = (_sessionListRevisions[trimmed] ?? 0) + 1;
    _sessionListRevisions[trimmed] = revision;
    final delta = SessionListDelta(
      workspaceId: trimmed,
      revision: revision,
      upserted: upserted,
      removed: removed,
    );
    if (!_sessionLists.isClosed) _sessionLists.add(delta);
    return delta;
  }

  /// Publishes one semantic content patch. Sequence is per session+seat stream.
  SessionContentDelta publishContentDelta({
    required String sessionId,
    required String memberId,
    required String kind,
    required String payload,
    bool partial = true,
  }) {
    final trimmedSession = sessionId.trim();
    final trimmedMember = memberId.trim();
    final streamKey = '$trimmedSession|$trimmedMember';
    final seq = (_contentDeltaSeq[streamKey] ?? 0) + 1;
    _contentDeltaSeq[streamKey] = seq;
    final event = SessionContentDelta(
      sessionId: trimmedSession,
      memberId: trimmedMember,
      seq: seq,
      baseSeq: seq - 1,
      epoch: epoch,
      kind: kind,
      payload: payload,
      partial: partial,
    );
    if (!_contentDeltas.isClosed) _contentDeltas.add(event);
    return event;
  }

  SessionAttention publishAttention({
    required String sessionId,
    required String kind,
    required String id,
    String memberId = '',
    String? turnId,
  }) {
    final event = SessionAttention(
      id: id,
      sessionId: sessionId,
      kind: kind,
      createdAt: _clock().toUtc(),
      memberId: memberId,
      turnId: turnId,
    );
    if (!_attention.isClosed) _attention.add(event);
    return event;
  }

  Future<void> dispose() async {
    await _deltas.close();
    await _content.close();
    await _contentDeltas.close();
    await _sessionLists.close();
    await _attention.close();
  }

  Map<String, SessionSeatActivity> _normalize(
    String sessionId,
    Iterable<SessionSeatActivity> seats,
  ) {
    final byMember = <String, SessionSeatActivity>{};
    for (final seat in seats) {
      if (seat.memberId.trim().isEmpty) continue;
      byMember[seat.memberId] = SessionSeatActivity(
        sessionId: sessionId,
        memberId: seat.memberId,
        state: seat.state,
        readyToChat: seat.readyToChat,
        disposition: seat.disposition,
        turnId: seat.turnId,
        updatedAt: seat.updatedAt,
      );
    }
    return byMember;
  }

  String _key(Iterable<SessionSeatActivity> seats) {
    final ordered = seats.toList()
      ..sort((a, b) => a.memberId.compareTo(b.memberId));
    return jsonEncode([for (final seat in ordered) seat.toJson()]);
  }
}
