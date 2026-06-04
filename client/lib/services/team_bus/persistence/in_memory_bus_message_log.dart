import 'bus_message_log.dart';
import '../team_message.dart';

/// 测试 / 无磁盘时的内存事件日志。
class InMemoryBusMessageLog implements BusMessageLog {
  final Map<String, List<LoggedMessage>> _byMember = {};

  List<LoggedMessage> _records(String memberId) =>
      _byMember.putIfAbsent(memberId, () => []);

  @override
  Future<void> appendMessage(
    String memberId,
    int seq,
    TeamMessage message,
    int createdAt,
  ) async {
    _records(memberId).add(
      LoggedMessage(seq: seq, message: message, createdAt: createdAt),
    );
  }

  @override
  Future<void> appendRead(String memberId, Iterable<int> seqs, int at) async {
    final set = seqs.toSet();
    for (final r in _records(memberId)) {
      if (set.contains(r.seq)) r.read = true;
    }
  }

  @override
  Future<List<LoggedMessage>> load(String memberId) async {
    return [
      for (final r in _records(memberId))
        LoggedMessage(
          seq: r.seq,
          message: r.message,
          createdAt: r.createdAt,
          read: r.read,
        ),
    ]..sort((a, b) => a.seq.compareTo(b.seq));
  }
}
