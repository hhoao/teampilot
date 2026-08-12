import 'dart:async';

/// 投递 ACK 注册表：注入前注册 pending，hook 事件命中时完成。
/// 文本完全匹配（trim 后）；每个 seat 同时最多一个 pending。
final class PromptSubmitAckTracker {
  final Map<String, _Pending> _pending = {};

  Future<bool> register({
    required String sessionId,
    required String memberId,
    required String text,
  }) {
    final key = _key(sessionId, memberId);
    final existing = _pending.remove(key);
    existing?.completer.complete(false);
    final completer = Completer<bool>();
    _pending[key] = _Pending(
      text: text.trim(),
      completer: completer,
    );
    return completer.future;
  }

  bool tryAck({
    required String sessionId,
    required String memberId,
    required String text,
  }) {
    final pending = _pending.remove(_key(sessionId, memberId));
    if (pending == null) return false;
    if (pending.text != text.trim()) {
      // 不匹配：不消耗 pending（等真正命中或超时清理）
      _pending[_key(sessionId, memberId)] = pending;
      return false;
    }
    pending.completer.complete(true);
    return true;
  }

  void clear(String sessionId, String memberId) {
    final removed = _pending.remove(_key(sessionId, memberId));
    if (removed != null && !removed.completer.isCompleted) {
      removed.completer.complete(false);
    }
  }

  static String _key(String sessionId, String memberId) =>
      '${sessionId.trim()}\u0000${memberId.trim()}';
}

final class _Pending {
  const _Pending({required this.text, required this.completer});
  final String text;
  final Completer<bool> completer;
}
