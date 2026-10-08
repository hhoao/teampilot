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

  /// 广播扇出深度计数：仅 [TeamBus.broadcast] 每跳 +1，超 maxHop 丢弃，防广播风暴。
  /// 注意：点对点 `send_message` 不经总线自动转发（由 agent 主动发起），故此计数
  /// **不**保护 A↔B 直接互发的 ping-pong 循环——那需由 agent 行为层面约束。
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
