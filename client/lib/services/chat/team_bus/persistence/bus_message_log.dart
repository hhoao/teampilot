import '../team_message.dart';

/// 日志里的一条消息(含 seq / 时间戳 / 已读标记)。read 由 read-event 回放得出。
class LoggedMessage {
  LoggedMessage({
    required this.seq,
    required this.message,
    required this.createdAt,
    this.read = false,
  });

  final int seq;
  final TeamMessage message;
  final int createdAt;
  bool read;

  bool get isUnread => !read;
}

/// 单一事实源:每成员一条 **append-only 事件日志**。两类事件——投递(message)与
/// 已读(read)——都是 O(1) 追加,无整文件重写;[load] 回放得到当前未读集。
///
/// 不再有热/冷双源对账:内存工作集由 [MemberInbox] 独占维护,日志只负责持久化与
/// 重启恢复。
abstract interface class BusMessageLog {
  /// 追加一条投递事件。
  Future<void> appendMessage(
    String memberId,
    int seq,
    TeamMessage message,
    int createdAt,
  );

  /// 追加一批已读事件。
  Future<void> appendRead(String memberId, Iterable<int> seqs, int at);

  /// 回放全部事件,按 seq 升序返回(已读标记已解析)。
  Future<List<LoggedMessage>> load(String memberId);
}
