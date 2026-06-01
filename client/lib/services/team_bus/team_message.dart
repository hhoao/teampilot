/// 总线上流转的单条消息（不可变）。
class TeamMessage {
  const TeamMessage({
    required this.id,
    required this.from,
    required this.to,
    required this.content,
    this.hop = 0,
  });

  /// 唯一 id（排序 / 去重）。
  final String id;

  /// 发送方 memberId（或 'user' / 'system'）。
  final String from;

  /// 目标 memberId；广播时为 '*'。
  final String to;

  final String content;

  /// 防环：每次转发 +1。
  final int hop;

  TeamMessage copyWith({
    String? id,
    String? from,
    String? to,
    String? content,
    int? hop,
  }) {
    return TeamMessage(
      id: id ?? this.id,
      from: from ?? this.from,
      to: to ?? this.to,
      content: content ?? this.content,
      hop: hop ?? this.hop,
    );
  }
}
