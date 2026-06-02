import 'dart:async';

import 'team_message.dart';

/// 每个成员一个信箱。`wait_for_message` 的阻塞接收落在这里。
class Mailbox {
  Mailbox({Duration debounce = const Duration(milliseconds: 50)})
    : _debounce = debounce;

  final Duration _debounce;
  final List<TeamMessage> _queue = [];
  Completer<List<TeamMessage>>? _waiter;
  Timer? _flushTimer;

  bool get isEmpty => _queue.isEmpty;

  int get unreadCount => _queue.length;

  /// 投递。有等待者→debounce 后批量唤醒；否则入队。
  void deliver(TeamMessage message) {
    _queue.add(message);
    if (_waiter == null) return; // 没人等：留在队列
    _flushTimer?.cancel();
    _flushTimer = Timer(_debounce, _flush);
  }

  /// 阻塞到有消息；[timeout] 为 null 时无限等待（mixed bus 默认）。
  /// 非空批=真消息；空批仅在有 timeout 且到期时出现。
  Future<List<TeamMessage>> waitBatch({Duration? timeout}) {
    if (_queue.isNotEmpty) {
      return Future.value(_drain());
    }
    final completer = Completer<List<TeamMessage>>();
    _waiter = completer;
    Timer? timer;
    if (timeout != null) {
      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          _waiter = null;
          completer.complete(const <TeamMessage>[]);
        }
      });
    }
    return completer.future.whenComplete(() => timer?.cancel());
  }

  List<TeamMessage> drainAll() => _drain();

  List<TeamMessage> _drain() {
    final batch = List<TeamMessage>.unmodifiable(_queue);
    _queue.clear();
    return batch;
  }

  void _flush() {
    final waiter = _waiter;
    if (waiter == null || waiter.isCompleted) return;
    _waiter = null;
    waiter.complete(_drain());
  }
}
