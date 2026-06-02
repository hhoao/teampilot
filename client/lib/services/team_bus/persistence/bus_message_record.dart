import '../team_message.dart';

/// 持久层一行：消息 + 时间戳 + 已读标记。
class BusMessageRecord {
  const BusMessageRecord({
    required this.message,
    required this.createdAt,
    this.readAt,
  });

  factory BusMessageRecord.fromJson(Map<String, Object?> json) {
    return BusMessageRecord(
      message: TeamMessage(
        id: json['id'] as String? ?? '',
        from: json['from'] as String? ?? '',
        to: json['to'] as String? ?? '',
        content: json['content'] as String? ?? '',
        hop: (json['hop'] as num?)?.toInt() ?? 0,
      ),
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      readAt: (json['readAt'] as num?)?.toInt(),
    );
  }

  final TeamMessage message;
  final int createdAt;
  final int? readAt;

  bool get isUnread => readAt == null;

  Map<String, Object?> toJson() => {
    'id': message.id,
    'from': message.from,
    'to': message.to,
    'content': message.content,
    'hop': message.hop,
    'createdAt': createdAt,
    if (readAt != null) 'readAt': readAt,
  };

  BusMessageRecord markRead(int at) {
    if (readAt != null) return this;
    return BusMessageRecord(message: message, createdAt: createdAt, readAt: at);
  }
}
