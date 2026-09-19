import '../team_message.dart';

/// 分页读取 bus 邮件的结果。
class BusMessagePage {
  const BusMessagePage({
    required this.messages,
    required this.hasMore,
    this.nextAfterId,
    this.totalUnread = 0,
  });

  final List<TeamMessage> messages;
  final bool hasMore;

  /// 下一页传 `after_id`。
  final String? nextAfterId;
  final int totalUnread;
}
