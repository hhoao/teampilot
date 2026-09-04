import 'dart:async';

/// Reply for a held Claude-family ExitPlanMode `PreToolUse` HTTP hook.
final class ExitPlanModeHookReply {
  const ExitPlanModeHookReply.allow() : deny = false;
  const ExitPlanModeHookReply.deny() : deny = true;

  final bool deny;

  /// Claude-family `PreToolUse` response for a completed held hook.
  Map<String, Object?> toHookResponse() => {
    'hookSpecificOutput': {
      'hookEventName': 'PreToolUse',
      'permissionDecision': deny ? 'deny' : 'allow',
      if (deny) 'permissionDecisionReason': 'User rejected the plan',
    },
  };
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
    final completer = _waiters.remove(_key(sessionId, memberId, toolUseId));
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

  /// Completes every held hook for one seat (plan approval without a
  /// tool_use_id — e.g. the card re-rendered from a PermissionRequest event).
  bool completeSeat({
    required String sessionId,
    required String memberId,
    required ExitPlanModeHookReply reply,
  }) {
    final prefix = '${sessionId.trim()}/${memberId.trim()}/';
    var completed = false;
    for (final key in _waiters.keys.toList()) {
      if (!key.startsWith(prefix)) continue;
      final c = _waiters.remove(key);
      if (c != null && !c.isCompleted) {
        c.complete(reply);
        completed = true;
      }
    }
    return completed;
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

/// Reply for a held Claude-family `PermissionRequest` (`ExitPlanMode`) hook —
/// the official `decision` object that skips the native TUI prompt.
final class ExitPlanPermissionRequestReply {
  const ExitPlanPermissionRequestReply.allow() : deny = false;
  const ExitPlanPermissionRequestReply.deny() : deny = true;

  final bool deny;

  /// Claude-family `PermissionRequest` response for a completed held hook.
  Map<String, Object?> toHookResponse() => {
    'hookSpecificOutput': {
      'hookEventName': 'PermissionRequest',
      'decision': {
        'behavior': deny ? 'deny' : 'allow',
        if (deny) 'message': 'User rejected the plan',
      },
    },
  };
}

/// Held Claude `PermissionRequest` (`ExitPlanMode`) HTTP hooks.
///
/// `PermissionRequest` payloads carry no `tool_use_id`, so waiters and the
/// chat-approval decision memory are keyed by seat + plan fingerprint: a plan
/// the user already approved (or rejected) from the chat card auto-applies to
/// the hook that arrives afterwards, without re-prompting.
final class ExitPlanPermissionRequestGate {
  final _waiters = <String, Completer<ExitPlanPermissionRequestReply>>{};
  final _remembered = <String, _RememberedPlanDecision>{};

  /// Waits for [complete] for one seat. A remembered decision for the same
  /// plan fingerprint resolves immediately (and is consumed); otherwise the
  /// hook is held until [complete] or [timeout] (null → fall through to the
  /// native TUI prompt).
  Future<ExitPlanPermissionRequestReply?> wait({
    required String sessionId,
    required String memberId,
    required String planFingerprint,
    Duration timeout = const Duration(hours: 24),
  }) async {
    final key = _key(sessionId, memberId);
    final remembered = _remembered.remove(key);
    if (remembered != null && remembered.fingerprint == planFingerprint) {
      return remembered.deny
          ? const ExitPlanPermissionRequestReply.deny()
          : const ExitPlanPermissionRequestReply.allow();
    }

    final existing = _waiters.remove(key);
    if (existing != null && !existing.isCompleted) {
      existing.complete(const ExitPlanPermissionRequestReply.deny());
    }
    final completer = Completer<ExitPlanPermissionRequestReply>();
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
    required ExitPlanPermissionRequestReply reply,
  }) {
    final completer = _waiters.remove(_key(sessionId, memberId));
    if (completer == null || completer.isCompleted) return false;
    completer.complete(reply);
    return true;
  }

  bool hasWaiter({required String sessionId, required String memberId}) {
    final completer = _waiters[_key(sessionId, memberId)];
    return completer != null && !completer.isCompleted;
  }

  /// Stores a chat-card decision for a PermissionRequest hook that has not
  /// arrived yet (single-slot per seat; overwritten by later decisions).
  void remember({
    required String sessionId,
    required String memberId,
    required bool deny,
    required String planFingerprint,
  }) {
    if (planFingerprint.trim().isEmpty) return;
    _remembered[_key(sessionId, memberId)] = _RememberedPlanDecision(
      fingerprint: planFingerprint.trim(),
      deny: deny,
    );
  }

  /// Drops the remembered decision for a seat. Called when a fresh
  /// ExitPlanMode `PreToolUse` plan prompt is held — an old decision must not
  /// auto-approve a later presentation of the same plan text.
  void forget({required String sessionId, required String memberId}) {
    _remembered.remove(_key(sessionId, memberId));
  }

  void clearSeat({required String sessionId, required String memberId}) {
    final key = _key(sessionId, memberId);
    _remembered.remove(key);
    final completer = _waiters.remove(key);
    if (completer != null && !completer.isCompleted) {
      completer.complete(const ExitPlanPermissionRequestReply.deny());
    }
  }

  void clearSession(String sessionId) {
    final prefix = '${sessionId.trim()}/';
    _remembered.removeWhere((key, _) => key.startsWith(prefix));
    final doomed = <String>[];
    for (final key in _waiters.keys) {
      if (key.startsWith(prefix)) doomed.add(key);
    }
    for (final key in doomed) {
      final c = _waiters.remove(key);
      if (c != null && !c.isCompleted) {
        c.complete(const ExitPlanPermissionRequestReply.deny());
      }
    }
  }

  String _key(String sessionId, String memberId) =>
      '${sessionId.trim()}/${memberId.trim()}';
}

final class _RememberedPlanDecision {
  const _RememberedPlanDecision({
    required this.fingerprint,
    required this.deny,
  });

  final String fingerprint;
  final bool deny;
}
