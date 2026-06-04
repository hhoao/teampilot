import 'dart:async';

/// 一次性取消信号。用于让阻塞中的 `wait_for_message` 在客户端断连时被解除，
/// 避免 [MemberInbox.waitAndTake] 的 Future 永不完成、member 永卡 `turnDoneBusWait`。
class CancellationToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  /// 被取消时完成（永不带错误）。
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}
