/// Semantic fact a user may want to know about. Unknown values decode to
/// [info] so a newer authority can add kinds without breaking older clients.
enum AttentionKind {
  idle,
  waiting,
  failed,
  info;

  static AttentionKind parse(Object? value) {
    final name = value is String ? value : '';
    for (final kind in AttentionKind.values) {
      if (kind.name == name) return kind;
    }
    return AttentionKind.info;
  }
}

/// One durable attention event.
///
/// `eventId` is the idempotency key; `seq` is assigned by the authority's
/// `AttentionLog` and is strictly monotonic inside one `(authorityId, epoch)`.
final class AttentionEvent {
  const AttentionEvent({
    required this.eventId,
    required this.authorityId,
    required this.epoch,
    required this.seq,
    required this.sessionId,
    required this.memberId,
    required this.kind,
    required this.occurredAt,
    required this.expiresAt,
    this.turnId,
    this.workspaceId = '',
    this.title = '',
    this.message = '',
    this.payload = const {},
  });

  final String eventId;
  final String authorityId;
  final int epoch;
  final int seq;
  final String sessionId;
  final String memberId;
  final String? turnId;
  final String workspaceId;
  final AttentionKind kind;
  final DateTime occurredAt;
  final DateTime expiresAt;
  final String title;
  final String message;
  final Map<String, Object?> payload;

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now.toUtc());

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'authorityId': authorityId,
    'epoch': epoch,
    'seq': seq,
    'sessionId': sessionId,
    if (memberId.isNotEmpty) 'memberId': memberId,
    if (turnId != null && turnId!.isNotEmpty) 'turnId': turnId,
    if (workspaceId.isNotEmpty) 'workspaceId': workspaceId,
    'kind': kind.name,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (title.isNotEmpty) 'title': title,
    if (message.isNotEmpty) 'message': message,
    if (payload.isNotEmpty) 'payload': payload,
  };

  static AttentionEvent? fromJson(Object? json) {
    if (json is! Map) return null;
    final eventId = json['eventId'];
    final authorityId = json['authorityId'];
    final sessionId = json['sessionId'];
    final kind = json['kind'];
    final epoch = json['epoch'];
    final seq = json['seq'];
    if (eventId is! String || eventId.isEmpty) return null;
    if (authorityId is! String || authorityId.isEmpty) return null;
    if (sessionId is! String || sessionId.isEmpty) return null;
    if (kind is! String) return null;
    if (epoch is! num || epoch <= 0) return null;
    if (seq is! num || seq <= 0) return null;
    final memberId = json['memberId'];
    final turnId = json['turnId'];
    final workspaceId = json['workspaceId'];
    final occurredAt = json['occurredAt'];
    final expiresAt = json['expiresAt'];
    final title = json['title'];
    final message = json['message'];
    final rawPayload = json['payload'];
    final parsedOccurred = occurredAt is String
        ? DateTime.tryParse(occurredAt)?.toUtc()
        : null;
    final parsedExpires = expiresAt is String
        ? DateTime.tryParse(expiresAt)?.toUtc()
        : null;
    if (parsedOccurred == null || parsedExpires == null) return null;
    return AttentionEvent(
      eventId: eventId,
      authorityId: authorityId,
      epoch: epoch.toInt(),
      seq: seq.toInt(),
      sessionId: sessionId,
      memberId: memberId is String ? memberId : '',
      turnId: turnId is String && turnId.isNotEmpty ? turnId : null,
      workspaceId: workspaceId is String ? workspaceId : '',
      kind: AttentionKind.parse(kind),
      occurredAt: parsedOccurred,
      expiresAt: parsedExpires,
      title: title is String ? title : '',
      message: message is String ? message : '',
      payload: rawPayload is Map
          ? {
              for (final entry in rawPayload.entries)
                entry.key.toString(): entry.value,
            }
          : const {},
    );
  }
}
