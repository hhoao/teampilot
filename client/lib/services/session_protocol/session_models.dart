import 'dart:convert';

/// Availability of one seat in the session plane.
///
/// Kept as a string (not an enum) so a newer authority can add states without
/// breaking older clients: unknown states are treated as non-busy.
final class SessionSeatActivity {
  const SessionSeatActivity({
    required this.sessionId,
    required this.memberId,
    required this.state,
    this.readyToChat = false,
    this.disposition = 'none',
    this.turnId,
    this.updatedAt = 0,
  });

  static const stateBooting = 'booting';
  static const stateWorking = 'working';
  static const stateIdle = 'idle';
  static const stateEnded = 'ended';

  final String sessionId;
  final String memberId;
  final String state;
  final bool readyToChat;
  final String disposition;
  final String? turnId;
  final int updatedAt;

  bool get isBusy => state == stateBooting || state == stateWorking;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'memberId': memberId,
    'state': state,
    'readyToChat': readyToChat,
    'disposition': disposition,
    if (turnId != null && turnId!.isNotEmpty) 'turnId': turnId,
    'updatedAt': updatedAt,
  };

  static SessionSeatActivity? fromJson(Object? json) {
    if (json is! Map) return null;
    final sessionId = json['sessionId'];
    final memberId = json['memberId'];
    final state = json['state'];
    if (sessionId is! String || memberId is! String || state is! String) {
      return null;
    }
    final ready = json['readyToChat'];
    final disposition = json['disposition'];
    final turnId = json['turnId'];
    final updatedAt = json['updatedAt'];
    return SessionSeatActivity(
      sessionId: sessionId,
      memberId: memberId,
      state: state,
      readyToChat: ready is bool ? ready : false,
      disposition: disposition is String ? disposition : 'none',
      turnId: turnId is String && turnId.isNotEmpty ? turnId : null,
      updatedAt: updatedAt is num ? updatedAt.toInt() : 0,
    );
  }
}

/// One delegated operation running on the authority (today: `turn.edit`).
///
/// Phases are strings, not an enum, so a newer authority can add one without
/// breaking a client that only knows the older set.
final class SessionOperation {
  const SessionOperation({
    required this.id,
    required this.kind,
    required this.sessionId,
    required this.memberId,
    required this.messageId,
    required this.phase,
    this.startedAt = 0,
    this.updatedAt = 0,
    this.errorCode = '',
  });

  static const kindTurnEdit = 'turn.edit';

  static const phaseQueued = 'queued';
  static const phaseRestoring = 'restoring';
  static const phaseRelaunching = 'relaunching';
  static const phaseDelivering = 'delivering';
  static const phaseAwaitingReplay = 'awaitingReplay';
  static const phaseConfirmed = 'confirmed';
  static const phaseFailed = 'failed';
  static const phaseCancelled = 'cancelled';

  final String id;
  final String kind;
  final String sessionId;
  final String memberId;
  final String messageId;
  final String phase;
  final int startedAt;
  final int updatedAt;
  final String errorCode;

  bool get isTerminal =>
      phase == phaseConfirmed ||
      phase == phaseFailed ||
      phase == phaseCancelled;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'sessionId': sessionId,
    'memberId': memberId,
    'messageId': messageId,
    'phase': phase,
    'startedAt': startedAt,
    'updatedAt': updatedAt,
    if (errorCode.isNotEmpty) 'errorCode': errorCode,
  };

  static SessionOperation? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final kind = json['kind'];
    final sessionId = json['sessionId'];
    final phase = json['phase'];
    if (id is! String || kind is! String || sessionId is! String) return null;
    if (phase is! String || phase.isEmpty) return null;
    final memberId = json['memberId'];
    final messageId = json['messageId'];
    final startedAt = json['startedAt'];
    final updatedAt = json['updatedAt'];
    final errorCode = json['errorCode'];
    return SessionOperation(
      id: id,
      kind: kind,
      sessionId: sessionId,
      memberId: memberId is String ? memberId : '',
      messageId: messageId is String ? messageId : '',
      phase: phase,
      startedAt: startedAt is num ? startedAt.toInt() : 0,
      updatedAt: updatedAt is num ? updatedAt.toInt() : 0,
      errorCode: errorCode is String ? errorCode : '',
    );
  }
}

/// One session's state at a revision.
final class SessionSnapshot {
  const SessionSnapshot({
    required this.sessionId,
    required this.epoch,
    required this.revision,
    required this.seats,
    this.operations = const [],
    this.authorityId = '',
    this.workspaceId = '',
  });

  final String sessionId;
  final int epoch;
  final int revision;
  final List<SessionSeatActivity> seats;

  /// Non-terminal delegated operations plus recently finished ones.
  final List<SessionOperation> operations;
  final String authorityId;
  final String workspaceId;

  bool get isBusy => seats.any((seat) => seat.isBusy);

  SessionOperation? operation(String operationId) {
    for (final operation in operations) {
      if (operation.id == operationId) return operation;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'epoch': epoch,
    'revision': revision,
    'authorityId': authorityId,
    if (workspaceId.isNotEmpty) 'workspaceId': workspaceId,
    'seats': [for (final seat in seats) seat.toJson()],
    if (operations.isNotEmpty)
      'operations': [for (final op in operations) op.toJson()],
  };

  static SessionSnapshot? fromJson(Object? json) {
    if (json is! Map) return null;
    final sessionId = json['sessionId'];
    if (sessionId is! String || sessionId.isEmpty) return null;
    final epoch = json['epoch'];
    final revision = json['revision'];
    final authorityId = json['authorityId'];
    final workspaceId = json['workspaceId'];
    final seats = <SessionSeatActivity>[];
    final rawSeats = json['seats'];
    if (rawSeats is List) {
      for (final raw in rawSeats) {
        final seat = SessionSeatActivity.fromJson(raw);
        if (seat != null) seats.add(seat);
      }
    }
    final operations = <SessionOperation>[];
    final rawOperations = json['operations'];
    if (rawOperations is List) {
      for (final raw in rawOperations) {
        final op = SessionOperation.fromJson(raw);
        if (op != null) operations.add(op);
      }
    }
    return SessionSnapshot(
      sessionId: sessionId,
      epoch: epoch is num ? epoch.toInt() : 0,
      revision: revision is num ? revision.toInt() : 0,
      seats: seats,
      operations: operations,
      authorityId: authorityId is String ? authorityId : '',
      workspaceId: workspaceId is String ? workspaceId : '',
    );
  }
}

/// Append-only state change for one session.
final class SessionDelta {
  const SessionDelta({
    required this.sessionId,
    required this.epoch,
    required this.baseRevision,
    required this.revision,
    required this.seats,
    this.operations = const [],
    this.removed = false,
    this.workspaceId = '',
  });

  final String sessionId;
  final int epoch;
  final int baseRevision;
  final int revision;
  final List<SessionSeatActivity> seats;

  /// Full operation list for the session; empty means "unchanged".
  final List<SessionOperation> operations;
  final bool removed;
  final String workspaceId;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'epoch': epoch,
    'baseRevision': baseRevision,
    'revision': revision,
    'removed': removed,
    if (workspaceId.isNotEmpty) 'workspaceId': workspaceId,
    'seats': [for (final seat in seats) seat.toJson()],
    if (operations.isNotEmpty)
      'operations': [for (final op in operations) op.toJson()],
  };

  static SessionDelta? fromJson(Object? json) {
    if (json is! Map) return null;
    final sessionId = json['sessionId'];
    if (sessionId is! String || sessionId.isEmpty) return null;
    final epoch = json['epoch'];
    final base = json['baseRevision'];
    final revision = json['revision'];
    final removed = json['removed'];
    final workspaceId = json['workspaceId'];
    final seats = <SessionSeatActivity>[];
    final rawSeats = json['seats'];
    if (rawSeats is List) {
      for (final raw in rawSeats) {
        final seat = SessionSeatActivity.fromJson(raw);
        if (seat != null) seats.add(seat);
      }
    }
    final operations = <SessionOperation>[];
    final rawOperations = json['operations'];
    if (rawOperations is List) {
      for (final raw in rawOperations) {
        final op = SessionOperation.fromJson(raw);
        if (op != null) operations.add(op);
      }
    }
    return SessionDelta(
      sessionId: sessionId,
      epoch: epoch is num ? epoch.toInt() : 0,
      baseRevision: base is num ? base.toInt() : 0,
      revision: revision is num ? revision.toInt() : 0,
      seats: seats,
      operations: operations,
      removed: removed is bool ? removed : false,
      workspaceId: workspaceId is String ? workspaceId : '',
    );
  }
}

/// Typed control request. Supported ops: `turn.cancel`, `turn.edit`,
/// `op.cancel`, `session.refresh`, `session.create`, `session.remove`.
final class SessionIntent {
  const SessionIntent({
    required this.id,
    required this.op,
    required this.sessionId,
    this.memberId = '',
    this.workspaceId = '',
    this.sessionListEntry,
    this.expectedEpoch,
    this.expectedTurnId,
    this.deadline,
    this.operationId = '',
    this.userMessageId = '',
    this.text = '',
  });

  final String id;
  final String op;
  final String sessionId;
  final String memberId;

  /// Workspace-scoped ops (for example `session.refresh`) target this id
  /// instead of a running session.
  final String workspaceId;

  /// `SessionListEntry.toJson()` for `session.create`.
  final Map<String, Object?>? sessionListEntry;
  final int? expectedEpoch;
  final String? expectedTurnId;
  final DateTime? deadline;

  /// `turn.edit` / `op.cancel`: the delegated operation this intent belongs to.
  /// Client-generated and used by the authority for idempotency.
  final String operationId;

  /// `turn.edit`: the user message being rewritten.
  final String userMessageId;

  /// `turn.edit`: the replacement text.
  final String text;

  Map<String, Object?> toJson() => {
    'id': id,
    'op': op,
    'sessionId': sessionId,
    'memberId': memberId,
    if (workspaceId.isNotEmpty) 'workspaceId': workspaceId,
    if (sessionListEntry != null) 'session': sessionListEntry,
    if (expectedEpoch != null) 'expectedEpoch': expectedEpoch,
    if (expectedTurnId != null) 'expectedTurnId': expectedTurnId,
    if (deadline != null) 'deadline': deadline!.toUtc().toIso8601String(),
    if (operationId.isNotEmpty) 'operationId': operationId,
    if (userMessageId.isNotEmpty) 'userMessageId': userMessageId,
    if (text.isNotEmpty) 'text': text,
  };

  static SessionIntent? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final op = json['op'];
    final sessionId = json['sessionId'];
    if (id is! String || op is! String || sessionId is! String) return null;
    final memberId = json['memberId'];
    final workspaceId = json['workspaceId'];
    final session = json['session'];
    final expectedEpoch = json['expectedEpoch'];
    final expectedTurnId = json['expectedTurnId'];
    final deadline = json['deadline'];
    final operationId = json['operationId'];
    final userMessageId = json['userMessageId'];
    final text = json['text'];
    return SessionIntent(
      id: id,
      op: op,
      sessionId: sessionId,
      memberId: memberId is String ? memberId : '',
      workspaceId: workspaceId is String ? workspaceId : '',
      sessionListEntry: session is Map
          ? {
              for (final entry in session.entries)
                entry.key.toString(): entry.value,
            }
          : null,
      expectedEpoch: expectedEpoch is num ? expectedEpoch.toInt() : null,
      expectedTurnId: expectedTurnId is String ? expectedTurnId : null,
      deadline: deadline is String ? DateTime.tryParse(deadline) : null,
      operationId: operationId is String ? operationId : '',
      userMessageId: userMessageId is String ? userMessageId : '',
      text: text is String ? text : '',
    );
  }
}

enum SessionIntentStatus { applied, noop, rejected, expired }

final class SessionIntentResult {
  const SessionIntentResult({
    required this.id,
    required this.status,
    this.epoch = 0,
    this.revision = 0,
    this.code = '',
    this.message = '',
  });

  final String id;
  final SessionIntentStatus status;
  final int epoch;
  final int revision;
  final String code;
  final String message;

  bool get ok =>
      status == SessionIntentStatus.applied ||
      status == SessionIntentStatus.noop;

  Map<String, Object?> toJson() => {
    'id': id,
    'status': status.name,
    'epoch': epoch,
    'revision': revision,
    if (code.isNotEmpty) 'code': code,
    if (message.isNotEmpty) 'message': message,
  };

  static SessionIntentResult? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final status = json['status'];
    if (id is! String || status is! String) return null;
    final epoch = json['epoch'];
    final revision = json['revision'];
    final code = json['code'];
    final message = json['message'];
    return SessionIntentResult(
      id: id,
      status: SessionIntentStatus.values.firstWhere(
        (value) => value.name == status,
        orElse: () => SessionIntentStatus.rejected,
      ),
      epoch: epoch is num ? epoch.toInt() : 0,
      revision: revision is num ? revision.toInt() : 0,
      code: code is String ? code : '',
      message: message is String ? message : '',
    );
  }
}

/// A transcript/screen invalidation signal. The client re-reads history; the
/// payload never carries the transcript itself.
final class SessionContentInvalidated {
  const SessionContentInvalidated({
    required this.sessionId,
    required this.seq,
    this.memberId = '',
    this.kind = 'transcript',
  });

  final String sessionId;
  final int seq;
  final String memberId;
  final String kind;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'seq': seq,
    'memberId': memberId,
    'kind': kind,
  };

  static SessionContentInvalidated? fromJson(Object? json) {
    if (json is! Map) return null;
    final sessionId = json['sessionId'];
    if (sessionId is! String || sessionId.isEmpty) return null;
    final seq = json['seq'];
    final memberId = json['memberId'];
    final kind = json['kind'];
    return SessionContentInvalidated(
      sessionId: sessionId,
      seq: seq is num ? seq.toInt() : 0,
      memberId: memberId is String ? memberId : '',
      kind: kind is String ? kind : 'transcript',
    );
  }
}

/// A coalesced content patch for one seat stream.
///
/// `kind` is semantic (`acp.messages`); `payload` is opaque to the protocol and
/// decoded by the feature that owns the kind.
final class SessionContentDelta {
  const SessionContentDelta({
    required this.sessionId,
    required this.memberId,
    required this.seq,
    required this.kind,
    required this.payload,
    this.epoch = 0,
    this.baseSeq = 0,
    this.partial = true,
  });

  final String sessionId;
  final String memberId;
  final int seq;
  final int baseSeq;
  final int epoch;
  final String kind;
  final String payload;

  /// False when [payload] is a full replacement rather than an incremental
  /// patch (for example, a message list was reordered).
  final bool partial;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'memberId': memberId,
    'seq': seq,
    'baseSeq': baseSeq,
    'epoch': epoch,
    'kind': kind,
    'payload': payload,
    'partial': partial,
  };

  static SessionContentDelta? fromJson(Object? json) {
    if (json is! Map) return null;
    final sessionId = json['sessionId'];
    final kind = json['kind'];
    final payload = json['payload'];
    if (sessionId is! String || sessionId.isEmpty || kind is! String) {
      return null;
    }
    if (payload is! String) return null;
    final memberId = json['memberId'];
    final seq = json['seq'];
    final base = json['baseSeq'];
    final epoch = json['epoch'];
    final partial = json['partial'];
    return SessionContentDelta(
      sessionId: sessionId,
      memberId: memberId is String ? memberId : '',
      seq: seq is num ? seq.toInt() : 0,
      baseSeq: base is num ? base.toInt() : 0,
      epoch: epoch is num ? epoch.toInt() : 0,
      kind: kind,
      payload: payload,
      partial: partial is bool ? partial : true,
    );
  }
}

/// One workspace's session-list delta, independent of running seats.
final class SessionListDelta {
  const SessionListDelta({
    required this.workspaceId,
    required this.revision,
    this.upserted = const [],
    this.removed = const [],
  });

  final String workspaceId;
  final int revision;

  /// `SessionListEntry.toJson()` rows.
  final List<Map<String, Object?>> upserted;
  final List<String> removed;

  Map<String, Object?> toJson() => {
    'workspaceId': workspaceId,
    'revision': revision,
    'upserted': upserted,
    'removed': removed,
  };

  static SessionListDelta? fromJson(Object? json) {
    if (json is! Map) return null;
    final workspaceId = json['workspaceId'];
    if (workspaceId is! String || workspaceId.isEmpty) return null;
    final revision = json['revision'];
    final rawUpserted = json['upserted'];
    final rawRemoved = json['removed'];
    return SessionListDelta(
      workspaceId: workspaceId,
      revision: revision is num ? revision.toInt() : 0,
      upserted: [
        if (rawUpserted is List)
          for (final item in rawUpserted)
            if (item is Map)
              {
                for (final entry in item.entries)
                  entry.key.toString(): entry.value,
              },
      ],
      removed: [
        if (rawRemoved is List)
          for (final item in rawRemoved)
            if (item is String && item.isNotEmpty) item,
      ],
    );
  }
}

/// Durable notification fact; the receiving client decides whether to show it.
final class SessionAttention {
  const SessionAttention({
    required this.id,
    required this.sessionId,
    required this.kind,
    required this.createdAt,
    this.memberId = '',
    this.turnId,
  });

  final String id;
  final String sessionId;
  final String kind;
  final DateTime createdAt;
  final String memberId;
  final String? turnId;

  Map<String, Object?> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'kind': kind,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (memberId.isNotEmpty) 'memberId': memberId,
    if (turnId != null) 'turnId': turnId,
  };

  static SessionAttention? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final sessionId = json['sessionId'];
    final kind = json['kind'];
    if (id is! String || sessionId is! String || kind is! String) return null;
    final createdAt = json['createdAt'];
    final memberId = json['memberId'];
    final turnId = json['turnId'];
    return SessionAttention(
      id: id,
      sessionId: sessionId,
      kind: kind,
      createdAt: createdAt is String
          ? DateTime.tryParse(createdAt) ?? DateTime.now().toUtc()
          : DateTime.now().toUtc(),
      memberId: memberId is String ? memberId : '',
      turnId: turnId is String ? turnId : null,
    );
  }
}

/// JSON helpers shared by the envelope and tests.
Map<String, Object?> asJsonMap(Object? value) {
  if (value is! Map) return const {};
  return {for (final entry in value.entries) entry.key.toString(): entry.value};
}

String jsonText(Object? value) => value is String ? value : jsonEncode(value);
