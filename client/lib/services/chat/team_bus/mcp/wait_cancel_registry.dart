import '../cancellation.dart';

/// Maps in-flight MCP tool `requestId` → [CancellationToken] for streaming
/// `wait_for_message`. [notifications/cancelled] looks up and cancels here.
///
/// Also tracks the active wait per [memberId] so a newer wait supersedes a
/// stale overlapping stream (disconnect detection can lag ~progressInterval).
class WaitCancelRegistry {
  final Map<String, CancellationToken> _byRequestId = {};
  final Map<String, CancellationToken> _byMember = {};

  void register(
    Object? requestId,
    CancellationToken cancel, {
    String? memberId,
  }) {
    if (memberId != null && memberId.isNotEmpty) {
      final prev = _byMember[memberId];
      if (prev != null && identical(prev, cancel) == false) {
        prev.cancel(WaitCancelReason.superseded);
      }
      _byMember[memberId] = cancel;
    }
    if (requestId == null) return;
    _byRequestId[_key(requestId)] = cancel;
  }

  void unregister(
    Object? requestId, {
    String? memberId,
    CancellationToken? cancel,
  }) {
    if (requestId != null) {
      _byRequestId.remove(_key(requestId));
    }
    if (memberId != null &&
        memberId.isNotEmpty &&
        cancel != null &&
        identical(_byMember[memberId], cancel)) {
      _byMember.remove(memberId);
    }
  }

  /// Returns true when a matching in-flight wait was cancelled.
  bool cancel(Object? requestId) {
    if (requestId == null) return false;
    final token = _byRequestId.remove(_key(requestId));
    if (token == null) return false;
    token.cancel(WaitCancelReason.mcpCancelled);
    return true;
  }

  String _key(Object id) => id.toString();
}
