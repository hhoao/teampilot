import 'dart:async';

import 'team_message.dart';

/// 每个成员一个信箱。`wait_for_message` 的阻塞接收落在这里。
class Mailbox {
  Mailbox({Duration debounce = const Duration(milliseconds: 50)})
    : _debounce = debounce;

  final Duration _debounce;
  final List<TeamMessage> _queue = [];
  final Set<String> _queuedIds = {};
  Completer<List<TeamMessage>>? _waiter;
  Timer? _flushTimer;

  bool get isEmpty => _queue.isEmpty;

  int get unreadCount => _queue.length;

  /// 投递。有等待者→debounce 后批量唤醒；否则入队。按 [TeamMessage.id] 去重。
  void deliver(TeamMessage message) {
    if (_queuedIds.contains(message.id)) return;
    _queuedIds.add(message.id);
    _queue.add(message);
    if (_waiter == null) return;
    _flushTimer?.cancel();
    _flushTimer = Timer(_debounce, _flush);
  }

  /// 从热队列移除（冷层已 mark read 时避免 wait 重复投递）。
  void removeByIds(Set<String> ids) {
    if (ids.isEmpty) return;
    _queue.removeWhere((m) {
      if (ids.contains(m.id)) {
        _queuedIds.remove(m.id);
        return true;
      }
      return false;
    });
  }

  /// 阻塞到有消息；[timeout] 为 null 时无限等待（mixed bus 默认）。
  Future<List<TeamMessage>> waitBatch({Duration? timeout}) {
    if (_queue.isNotEmpty) {
      return Future.value(_drain());
    }
    // 重入保护：协议上每成员串行，但若上一个 waiter 仍挂着（未完成）就被覆盖，
    // 它的 future 将永不完成 → 泄漏。先以空批结束旧 waiter。
    final stale = _waiter;
    if (stale != null && !stale.isCompleted) {
      stale.complete(const <TeamMessage>[]);
    }
    final completer = Completer<List<TeamMessage>>();
    _waiter = completer;
    Timer? timer;
    if (timeout != null) {
      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          if (identical(_waiter, completer)) _waiter = null;
          // 超时即放弃本次等待：取消可能挂起的 debounce flush，避免它之后空跑。
          _flushTimer?.cancel();
          _flushTimer = null;
          completer.complete(const <TeamMessage>[]);
        }
      });
    }
    return completer.future.whenComplete(() => timer?.cancel());
  }

  /// 拆 session：取消 timer、以空批结束挂起的 waiter，防 Timer / Future 泄漏。
  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(const <TeamMessage>[]);
    }
    _queue.clear();
    _queuedIds.clear();
  }

  List<TeamMessage> drainAll() => _drain();

  List<TeamMessage> peekAll() => List<TeamMessage>.unmodifiable(_queue);

  List<TeamMessage> _drain() {
    final batch = List<TeamMessage>.unmodifiable(_queue);
    _queue.clear();
    for (final m in batch) {
      _queuedIds.remove(m.id);
    }
    return batch;
  }

  void _flush() {
    final waiter = _waiter;
    if (waiter == null || waiter.isCompleted) return;
    _waiter = null;
    waiter.complete(_drain());
  }
}
