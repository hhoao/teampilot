import 'dart:async';

/// Why a blocked `wait_for_message` was cancelled.
enum WaitCancelReason {
  /// MCP client sent `notifications/cancelled` (e.g. tool timeout); agent loop
  /// typically continues → bus may resume [MemberActivity.active].
  mcpCancelled,

  /// SSE/socket disconnect, session stop, or other generic cancel →
  /// [MemberActivity.turnDoneReady].
  disconnected,
}

/// 一次性取消信号。用于让阻塞中的 `wait_for_message` 在客户端断连时被解除，
/// 避免 [MemberInbox.waitAndTake] 的 Future 永不完成、member 永卡 `turnDoneBusWait`。
class CancellationToken {
  final Completer<void> _completer = Completer<void>();

  WaitCancelReason? _reason;

  bool get isCancelled => _completer.isCompleted;

  /// Set when [cancel] runs; null before cancellation.
  WaitCancelReason? get cancelReason => _reason;

  /// 被取消时完成（永不带错误）。
  Future<void> get whenCancelled => _completer.future;

  void cancel([WaitCancelReason reason = WaitCancelReason.disconnected]) {
    if (_completer.isCompleted) return;
    _reason = reason;
    _completer.complete();
  }
}
