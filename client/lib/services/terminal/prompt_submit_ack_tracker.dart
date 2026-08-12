import 'dart:async';

/// 投递 ACK 注册表：注入前注册 pending，hook 事件命中时完成。
/// 文本完全匹配（trim 后）；每个 seat 同时最多一个 pending。
///
/// 命中同时记录 seat 级 acked 标记（[isAcked]），供探针 outcome 侧判断：
/// 即使 pending 已被消费/清除，标记仍保留到下一次 [register]（新一轮投递）
/// 或 [clear] 显式清除——保证"ACK 先到、crStuck outcome 后到"时重试被跳过。
final class PromptSubmitAckTracker {
  final Map<String, _Pending> _pending = {};
  final Set<String> _acked = {};

  Future<bool> register({
    required String sessionId,
    required String memberId,
    required String text,
  }) {
    final key = _key(sessionId, memberId);
    final existing = _pending.remove(key);
    existing?.completer.complete(false);
    _acked.remove(key);
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
    final key = _key(sessionId, memberId);
    final pending = _pending.remove(key);
    if (pending == null) return false;
    if (pending.text != text.trim()) {
      // 不匹配：不消耗 pending（等真正命中或超时清理）
      _pending[key] = pending;
      return false;
    }
    _acked.add(key);
    pending.completer.complete(true);
    return true;
  }

  /// 该 seat 最近一次投递是否已被 hook ACK 命中（本轮投递内有效）。
  bool isAcked({
    required String sessionId,
    required String memberId,
  }) =>
      _acked.contains(_key(sessionId, memberId));

  void clear(String sessionId, String memberId) {
    final key = _key(sessionId, memberId);
    final removed = _pending.remove(key);
    if (removed != null && !removed.completer.isCompleted) {
      removed.completer.complete(false);
    }
    _acked.remove(key);
  }

  static String _key(String sessionId, String memberId) =>
      '${sessionId.trim()}\u0000${memberId.trim()}';
}

final class _Pending {
  const _Pending({required this.text, required this.completer});
  final String text;
  final Completer<bool> completer;
}
