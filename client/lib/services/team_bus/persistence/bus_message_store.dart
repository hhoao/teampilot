import 'bus_message_page.dart';
import '../team_message.dart';

/// 冷层：append-only 持久化 + 分页 / 未读计数（热层 [Mailbox] 仍负责 wait 唤醒）。
abstract class BusMessageStore {
  Future<void> append(String memberId, TeamMessage message);

  Future<BusMessagePage> readPage(
    String memberId, {
    String? afterId,
    int limit = 20,
    bool unreadOnly = true,
    bool markRead = false,
  });

  Future<void> markRead(String memberId, Iterable<String> messageIds);

  Future<int> unreadCount(String memberId);

  /// 恢复 session 时把未读灌回内存信箱（dedupe by id）。
  Future<List<TeamMessage>> loadUnread(String memberId);
}
