import 'dart:async';

/// Reply for a held Claude-family ExitPlanMode `PreToolUse` HTTP hook.
final class ExitPlanModeHookReply {
  const ExitPlanModeHookReply.allow() : deny = false;
  const ExitPlanModeHookReply.deny() : deny = true;

  final bool deny;
}

/// Holds open Claude `PreToolUse` HTTP hooks for ExitPlanMode until the chat
/// card approves/rejects (official `permissionDecision` allow/deny path).
///
/// Parallel to `AskUserQuestionHookGate`; a distinct reply type (allow/deny,
/// no answers payload) keeps the two gates independent.
final class ExitPlanModeHookGate {
  final _waiters = <String, Completer<ExitPlanModeHookReply>>{};

  /// Waits for [complete] with the same ids. Returns `null` on timeout so the
  /// handler can fall through to Claude's native TUI (`{}` response).
  Future<ExitPlanModeHookReply?> wait({
    required String sessionId,
    required String memberId,
    required String toolUseId,
    Duration timeout = const Duration(hours: 24),
  }) async {
    final key = _key(sessionId, memberId, toolUseId);
    final existing = _waiters.remove(key);
    if (existing != null && !existing.isCompleted) {
      existing.complete(const ExitPlanModeHookReply.deny());
    }
    final completer = Completer<ExitPlanModeHookReply>();
    _waiters[key] = completer;
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      return null;
    } finally {
      final current = _waiters[key];
      if (identical(current, completer)) {
        _waiters.remove(key);
      }
    }
  }

  /// Returns true when a waiter was completed (hook still open).
  bool complete({
    required String sessionId,
    required String memberId,
    required String toolUseId,
    required ExitPlanModeHookReply reply,
  }) {
    final completer = _waiters.remove(
      _key(sessionId, memberId, toolUseId),
    );
    if (completer == null || completer.isCompleted) return false;
    completer.complete(reply);
    return true;
  }

  bool hasWaiter({
    required String sessionId,
    required String memberId,
    required String toolUseId,
  }) {
    final completer = _waiters[_key(sessionId, memberId, toolUseId)];
    return completer != null && !completer.isCompleted;
  }

  void clearSeat({required String sessionId, required String memberId}) {
    final prefix = '${sessionId.trim()}/${memberId.trim()}/';
    final doomed = <String>[];
    for (final key in _waiters.keys) {
      if (key.startsWith(prefix)) doomed.add(key);
    }
    for (final key in doomed) {
      final c = _waiters.remove(key);
      if (c != null && !c.isCompleted) {
        c.complete(const ExitPlanModeHookReply.deny());
      }
    }
  }

  void clearSession(String sessionId) {
    final prefix = '${sessionId.trim()}/';
    final doomed = <String>[];
    for (final key in _waiters.keys) {
      if (key.startsWith(prefix)) doomed.add(key);
    }
    for (final key in doomed) {
      final c = _waiters.remove(key);
      if (c != null && !c.isCompleted) {
        c.complete(const ExitPlanModeHookReply.deny());
      }
    }
  }

  String _key(String sessionId, String memberId, String toolUseId) =>
      '${sessionId.trim()}/${memberId.trim()}/${toolUseId.trim()}';
}
