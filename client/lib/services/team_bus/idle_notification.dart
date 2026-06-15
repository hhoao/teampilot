import 'dart:convert';

/// 对齐 Claude Code `IdleNotificationMessage`（worker turn 结束 → leader inbox）。
enum IdleReason {
  available('available'),
  interrupted('interrupted'),
  failed('failed');

  const IdleReason(this.value);
  final String value;

  static IdleReason? tryParse(String? raw) {
    final v = raw?.trim();
    if (v == null || v.isEmpty) return null;
    for (final r in IdleReason.values) {
      if (r.value == v) return r;
    }
    return null;
  }
}

class IdleNotification {
  const IdleNotification({
    required this.from,
    required this.displayName,
    required this.timestampMs,
    this.idleReason = IdleReason.available,
    this.summary,
    this.completedTaskId,
    this.completedStatus,
    this.failureReason,
  });

  static const type = 'idle_notification';

  final String from;
  final String displayName;
  final int timestampMs;
  final IdleReason idleReason;
  final String? summary;
  final String? completedTaskId;
  final String? completedStatus;
  final String? failureReason;

  factory IdleNotification.fromWorker({
    required String memberId,
    required String displayName,
    IdleReason idleReason = IdleReason.available,
    String? summary,
    int? timestampMs,
  }) {
    return IdleNotification(
      from: memberId,
      displayName: displayName,
      timestampMs: timestampMs ?? DateTime.now().millisecondsSinceEpoch,
      idleReason: idleReason,
      summary: summary,
    );
  }

  factory IdleNotification.tryParse(String content) {
    final trimmed = content.trim();
    if (!trimmed.startsWith('{')) {
      throw FormatException('not json');
    }
    final json = jsonDecode(trimmed);
    if (json is! Map) throw FormatException('not object');
    final map = Map<String, Object?>.from(json);
    if (map['type'] != type) throw FormatException('not idle_notification');
    return IdleNotification(
      from: map['from'] as String? ?? '',
      displayName: map['displayName'] as String? ?? map['from'] as String? ?? '',
      timestampMs: _parseTimestampMs(map),
      idleReason:
          IdleReason.tryParse(map['idleReason'] as String?) ??
          IdleReason.available,
      summary: map['summary'] as String?,
      completedTaskId: map['completedTaskId'] as String?,
      completedStatus: map['completedStatus'] as String?,
      failureReason: map['failureReason'] as String?,
    );
  }

  static int _parseTimestampMs(Map<String, Object?> map) {
    final ms = map['timestampMs'];
    if (ms is num) return ms.toInt();
    final ts = map['timestamp'];
    if (ts is num) return ts.toInt();
    if (ts is String) {
      final parsed = DateTime.tryParse(ts);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    return 0;
  }

  static IdleNotification? parseTeamMessageContent(String content) {
    try {
      return IdleNotification.tryParse(content);
    } on Object {
      return null;
    }
  }

  String encode() => jsonEncode(toJson());

  Map<String, Object?> toJson() => {
    'type': type,
    'from': from,
    if (displayName.isNotEmpty) 'displayName': displayName,
    'timestamp': DateTime.fromMillisecondsSinceEpoch(timestampMs).toIso8601String(),
    'timestampMs': timestampMs,
    'idleReason': idleReason.value,
    if (summary != null && summary!.trim().isNotEmpty) 'summary': summary,
    if (completedTaskId != null && completedTaskId!.isNotEmpty)
      'completedTaskId': completedTaskId,
    if (completedStatus != null && completedStatus!.isNotEmpty)
      'completedStatus': completedStatus,
    if (failureReason != null && failureReason!.isNotEmpty)
      'failureReason': failureReason,
  };

  /// MCP `wait_for_message` / `read_messages` 人类可读格式。
  String formatForLeader() {
    final buffer = StringBuffer(
      'IDLE NOTIFICATION from $from (${displayName.isEmpty ? from : displayName})',
    );
    buffer.write('\nreason: ${idleReason.value}');
    if (summary != null && summary!.trim().isNotEmpty) {
      buffer.write('\nsummary: ${summary!.trim()}');
    }
    if (completedTaskId != null && completedTaskId!.isNotEmpty) {
      buffer.write('\ncompletedTaskId: $completedTaskId');
    }
    if (completedStatus != null && completedStatus!.isNotEmpty) {
      buffer.write('\ncompletedStatus: $completedStatus');
    }
    if (failureReason != null && failureReason!.isNotEmpty) {
      buffer.write('\nfailureReason: $failureReason');
    }
    buffer.write(
      '\n(hint: this teammate has STOPPED and has NO work in progress — this does '
      'NOT mean they are still busy. Take action now, do NOT silently go back to '
      'wait_for_message: if you delegated via the work queue, call '
      'list_tasks(status: done) to read their result; if you delegated via '
      'send_message, call read_messages to see their reply; if there is no '
      'result yet, send_message to ask for status or assign the next task.)',
    );
    return buffer.toString();
  }
}
