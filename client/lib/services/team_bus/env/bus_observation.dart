/// 总线产出的结构化领域事件(可观测性)。喂日志,也可喂 UI 活动时间线 ——
/// 把散落的 appLogger 字符串拼接收口成有类型的事件。
sealed class BusObservation {
  const BusObservation();
}

/// 消息成功路由到某成员信箱。
class MessageRouted extends BusObservation {
  const MessageRouted({required this.messageId, required this.to, required this.from});
  final String messageId;
  final String to;
  final String from;
}

/// 消息被丢弃(超 hop / 目标未知)。
class MessageDropped extends BusObservation {
  const MessageDropped({required this.messageId, required this.reason, this.to});
  final String messageId;
  final String reason;
  final String? to;
}

/// 成员被门铃唤醒(注入 stdin 提示)。
class MemberDoorbelled extends BusObservation {
  const MemberDoorbelled(this.memberId);
  final String memberId;
}

/// 一批未读被取走(wait_for_message 落点);[confirmed]/[rolledBack] 标记后续。
class BatchTaken extends BusObservation {
  const BatchTaken({required this.memberId, required this.count});
  final String memberId;
  final int count;
}

/// 取走的批次已确认已读(成功送达 CLI)。
class DeliveryConfirmed extends BusObservation {
  const DeliveryConfirmed({required this.memberId, required this.count});
  final String memberId;
  final int count;
}

/// 取走的批次被回滚(SSE 断连,放回信箱,未丢失)。
class DeliveryRolledBack extends BusObservation {
  const DeliveryRolledBack({required this.memberId, required this.count});
  final String memberId;
  final int count;
}
