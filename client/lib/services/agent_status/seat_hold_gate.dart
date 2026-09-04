import 'dart:async';

/// Generic single-slot, seat-keyed HTTP-hook hold.
///
/// One held waiter per `(sessionId, memberId)` seat. A newer [wait] resolves
/// the previous waiter with [staleReply]; [releaseHold] resolves `null` so the
/// gateway answers `{}` and the CLI's native prompt takes over; a timeout
/// resolves `null` the same way. Extracted from
/// `ExitPlanPermissionRequestGate` — that class keeps only its plan-fingerprint
/// decision memory on top of this primitive.
final class SeatHoldGate<TReply> {
  SeatHoldGate({required this.staleReply});

  /// Reply applied to a waiter replaced by a newer hold or cleared by
  /// [clearSeat] / [clearSession] (deny semantics for permissions).
  final TReply Function() staleReply;

  final _waiters = <String, Completer<TReply?>>{};

  Future<TReply?> wait({
    required String sessionId,
    required String memberId,
    Duration timeout = const Duration(hours: 24),
  }) async {
    final key = _key(sessionId, memberId);
    final existing = _waiters.remove(key);
    if (existing != null && !existing.isCompleted) {
      existing.complete(staleReply());
    }
    final completer = Completer<TReply?>();
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
    required TReply reply,
  }) {
    final completer = _waiters.remove(_key(sessionId, memberId));
    if (completer == null || completer.isCompleted) return false;
    completer.complete(reply);
    return true;
  }

  /// Active fall-through: resolves the held waiter with `null` so the gateway
  /// answers `{}` and the native TUI prompt appears.
  bool releaseHold({required String sessionId, required String memberId}) {
    final completer = _waiters.remove(_key(sessionId, memberId));
    if (completer == null || completer.isCompleted) return false;
    completer.complete(null);
    return true;
  }

  bool hasWaiter({required String sessionId, required String memberId}) {
    final completer = _waiters[_key(sessionId, memberId)];
    return completer != null && !completer.isCompleted;
  }

  void clearSeat({required String sessionId, required String memberId}) {
    final completer = _waiters.remove(_key(sessionId, memberId));
    if (completer != null && !completer.isCompleted) {
      completer.complete(staleReply());
    }
  }

  void clearSession(String sessionId) {
    final prefix = '${sessionId.trim()}/';
    final doomed = _waiters.keys
        .where((key) => key.startsWith(prefix))
        .toList();
    for (final key in doomed) {
      final completer = _waiters.remove(key);
      if (completer != null && !completer.isCompleted) {
        completer.complete(staleReply());
      }
    }
  }

  String _key(String sessionId, String memberId) =>
      '${sessionId.trim()}/${memberId.trim()}';
}
