import 'dart:async';

import 'cancellation.dart';
import 'persistence/bus_message_log.dart';
import 'persistence/bus_message_page.dart';
import 'team_message.dart';

/// 单个成员信箱:**内存未读工作集 + append-only 日志的唯一所有者**。
///
/// 取代旧的「热 Mailbox + 冷 Store,由 TeamBus 手工对账」双源模型。投递/已读/读取
/// 全部经此一处,内存与日志由它自己保持一致——消除了去重 / removeByIds / 跨对象
/// markRead 那一整类 bug。
///
/// 投递对调用方是同步的(立即进未读集),持久化 fire-and-forget(崩溃只丢未落盘的
/// 尾部,语义同旧实现)。`wait` 落在内存信号上,被取消即解除。
class MemberInbox {
  MemberInbox({
    required this.memberId,
    Duration debounce = const Duration(milliseconds: 50),
  }) : _debounce = debounce;

  final String memberId;
  final Duration _debounce;

  // 持久化(可选;测试 / 无磁盘时为空)。
  BusMessageLog? _log;
  int Function() _clock = () => DateTime.now().millisecondsSinceEpoch;

  final List<LoggedMessage> _unread = [];
  final Set<String> _knownIds = {};
  int _nextSeq = 0;

  Completer<void>? _waiter;
  Timer? _flushTimer;

  bool get isEmpty => _unread.isEmpty;
  int get unreadCount => _unread.length;

  /// 绑定日志层(由 [TeamBus.declareMember] 注入)。
  void bindLog(BusMessageLog log, int Function() clock) {
    _log = log;
    _clock = clock;
  }

  /// 开 session:回放日志 → 重建未读集与 seq 游标(按 id 去重)。
  Future<void> rehydrate() async {
    final log = _log;
    if (log == null) return;
    final records = await log.load(memberId);
    for (final r in records) {
      if (r.seq >= _nextSeq) _nextSeq = r.seq + 1;
      if (_knownIds.contains(r.message.id)) continue; // 幂等 + 不覆盖已投递
      _knownIds.add(r.message.id);
      if (r.isUnread) _unread.add(r);
    }
  }

  /// 投递(同步入未读集 + 异步落盘 + 唤醒等待者)。按 [TeamMessage.id] 去重。
  void deliver(TeamMessage message) {
    if (_knownIds.contains(message.id)) return;
    _knownIds.add(message.id);
    final rec = LoggedMessage(
      seq: _nextSeq++,
      message: message,
      createdAt: _clock(),
    );
    _unread.add(rec);
    _persist(() => _log?.appendMessage(memberId, rec.seq, message, rec.createdAt));
    if (_waiter == null) return;
    _flushTimer?.cancel();
    _flushTimer = Timer(_debounce, _flush);
  }

  /// 当前未读快照(只读,不消费)。
  List<TeamMessage> peekAll() =>
      List<TeamMessage>.unmodifiable(_unread.map((r) => r.message));

  /// 阻塞到有未读,然后 **取走**(移出内存,但尚未持久化已读——等 [confirm])。
  /// [cancel] 触发或 [timeout] 到达即以空批返回。
  Future<List<TeamMessage>> waitAndTake({
    Duration? timeout,
    CancellationToken? cancel,
  }) {
    if (_unread.isNotEmpty) return Future.value(_take());
    if (cancel?.isCancelled ?? false) {
      return Future.value(const <TeamMessage>[]);
    }
    final stale = _waiter;
    if (stale != null && !stale.isCompleted) {
      stale.complete();
    }
    final completer = Completer<void>();
    _waiter = completer;

    void abandon() {
      if (completer.isCompleted) return;
      if (identical(_waiter, completer)) _waiter = null;
      _flushTimer?.cancel();
      _flushTimer = null;
      completer.complete();
    }

    final timer = timeout != null ? Timer(timeout, abandon) : null;
    cancel?.whenCancelled.then((_) => abandon());
    return completer.future.whenComplete(() => timer?.cancel()).then((_) {
      return _take();
    });
  }

  /// 已读确认:对取走的批次落 read 事件(append-only)。配合 [waitAndTake] 实现
  /// 「先投递确认、后标记已读」的至少一次语义。
  Future<void> confirmRead(Iterable<String> messageIds) async {
    final ids = messageIds.toSet();
    if (ids.isEmpty) return;
    final seqs = _seqsForTakenIds(ids);
    if (seqs.isEmpty) return;
    await _log?.appendRead(memberId, seqs, _clock());
  }

  /// 回滚:把取走但未确认的批次放回未读集(投递失败/断连时)。
  void restore(List<TeamMessage> batch) {
    if (batch.isEmpty) return;
    // 还原到队首并保持 seq 顺序;按 id 防重复。
    final restored = <LoggedMessage>[];
    for (final m in batch) {
      final seq = _takenSeqById.remove(m.id);
      if (seq == null) continue;
      restored.add(LoggedMessage(seq: seq, message: m, createdAt: _clock()));
    }
    if (restored.isEmpty) return;
    _unread.insertAll(0, restored);
    _unread.sort((a, b) => a.seq.compareTo(b.seq));
  }

  /// 分页读取(read_messages 落点)。默认只读未读、不消费;[markRead] 为真时消费
  /// 返回页(移出未读集 + 落 read 事件)。
  Future<BusMessagePage> readPage({
    String? afterId,
    int limit = 20,
    bool unreadOnly = true,
    bool markRead = false,
  }) async {
    final records = unreadOnly
        ? List<LoggedMessage>.from(_unread)
        : (await _log?.load(memberId) ?? List<LoggedMessage>.from(_unread));
    final page = _slice(records, afterId: afterId, limit: limit);
    if (markRead && page.messages.isNotEmpty) {
      final ids = page.messages.map((m) => m.id).toSet();
      final seqs = <int>[];
      _unread.removeWhere((r) {
        if (ids.contains(r.message.id)) {
          seqs.add(r.seq);
          return true;
        }
        return false;
      });
      if (seqs.isNotEmpty) await _log?.appendRead(memberId, seqs, _clock());
    }
    return page;
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    _unread.clear();
  }

  // --- internals ---

  /// 取走时记下 id→seq,供 [confirmRead] / [restore] 用。
  final Map<String, int> _takenSeqById = {};

  List<TeamMessage> _take() {
    final batch = <TeamMessage>[];
    for (final r in _unread) {
      batch.add(r.message);
      _takenSeqById[r.message.id] = r.seq;
    }
    _unread.clear();
    return List<TeamMessage>.unmodifiable(batch);
  }

  List<int> _seqsForTakenIds(Set<String> ids) {
    final seqs = <int>[];
    for (final id in ids) {
      final seq = _takenSeqById.remove(id);
      if (seq != null) seqs.add(seq);
    }
    return seqs;
  }

  void _flush() {
    final waiter = _waiter;
    if (waiter == null || waiter.isCompleted) return;
    _waiter = null;
    waiter.complete();
  }

  void _persist(Future<void>? Function() op) {
    final future = op();
    if (future == null) return;
    unawaited(future.catchError((Object _) {}));
  }

  BusMessagePage _slice(
    List<LoggedMessage> records, {
    required String? afterId,
    required int limit,
  }) {
    final totalUnread = _unread.length;
    var start = 0;
    if (afterId != null && afterId.isNotEmpty) {
      final anchor = records.indexWhere((r) => r.message.id == afterId);
      start = anchor < 0 ? records.length : anchor + 1;
    }
    final safeLimit = limit.clamp(1, 100);
    final end = (start + safeLimit).clamp(0, records.length);
    final slice = start <= end ? records.sublist(start, end) : <LoggedMessage>[];
    final hasMore = end < records.length;
    return BusMessagePage(
      messages: [for (final r in slice) r.message],
      hasMore: hasMore,
      nextAfterId: hasMore && slice.isNotEmpty ? slice.last.message.id : null,
      totalUnread: totalUnread,
    );
  }
}
