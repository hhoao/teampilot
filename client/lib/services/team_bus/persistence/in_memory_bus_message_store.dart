import 'bus_message_page.dart';
import 'bus_message_record.dart';
import 'bus_message_store.dart';
import '../team_message.dart';

/// 测试 / 无磁盘时的内存冷层。
class InMemoryBusMessageStore implements BusMessageStore {
  InMemoryBusMessageStore({int Function()? clock})
    : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Map<String, List<BusMessageRecord>> _byMember = {};
  final int Function() _clock;

  List<BusMessageRecord> _records(String memberId) =>
      _byMember.putIfAbsent(memberId, () => []);

  @override
  Future<void> append(String memberId, TeamMessage message) async {
    _records(memberId).add(
      BusMessageRecord(message: message, createdAt: _clock()),
    );
  }

  @override
  Future<BusMessagePage> readPage(
    String memberId, {
    String? afterId,
    int limit = 20,
    bool unreadOnly = true,
    bool markRead = false,
  }) async {
    final page = _slice(
      _records(memberId),
      afterId: afterId,
      limit: limit,
      unreadOnly: unreadOnly,
    );
    if (markRead && page.messages.isNotEmpty) {
      await this.markRead(memberId, page.messages.map((m) => m.id));
    }
    return page;
  }

  @override
  Future<void> markRead(String memberId, Iterable<String> messageIds) async {
    final ids = messageIds.toSet();
    if (ids.isEmpty) return;
    final at = _clock();
    final list = _records(memberId);
    for (var i = 0; i < list.length; i++) {
      if (ids.contains(list[i].message.id)) {
        list[i] = list[i].markRead(at);
      }
    }
  }

  @override
  Future<int> unreadCount(String memberId) async {
    return _records(memberId).where((r) => r.isUnread).length;
  }

  @override
  Future<List<TeamMessage>> loadUnread(String memberId) async {
    return [
      for (final r in _records(memberId))
        if (r.isUnread) r.message,
    ];
  }

  BusMessagePage _slice(
    List<BusMessageRecord> records, {
    required String? afterId,
    required int limit,
    required bool unreadOnly,
  }) {
    final filtered = [
      for (final r in records)
        if (!unreadOnly || r.isUnread) r,
    ];
    final totalUnread = records.where((r) => r.isUnread).length;
    var start = 0;
    if (afterId != null && afterId.isNotEmpty) {
      final anchor = records.indexWhere((r) => r.message.id == afterId);
      if (anchor >= 0) {
        final next = filtered.indexWhere((r) {
          final pos = records.indexWhere((x) => x.message.id == r.message.id);
          return pos > anchor;
        });
        start = next < 0 ? filtered.length : next;
      } else {
        final cursor = filtered.indexWhere((r) => r.message.id == afterId);
        start = cursor < 0 ? filtered.length : cursor + 1;
      }
    }
    final end = (start + limit).clamp(0, filtered.length);
    final slice = filtered.sublist(start, end);
    final hasMore = end < filtered.length;
    return BusMessagePage(
      messages: [for (final r in slice) r.message],
      hasMore: hasMore,
      nextAfterId: hasMore ? slice.last.message.id : null,
      totalUnread: totalUnread,
    );
  }
}
