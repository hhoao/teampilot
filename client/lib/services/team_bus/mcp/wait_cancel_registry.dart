import '../cancellation.dart';

/// Maps in-flight MCP tool `requestId` → [CancellationToken] for streaming
/// `wait_for_message`. [notifications/cancelled] looks up and cancels here.
class WaitCancelRegistry {
  final Map<String, CancellationToken> _byRequestId = {};

  void register(Object? requestId, CancellationToken cancel) {
    if (requestId == null) return;
    _byRequestId[_key(requestId)] = cancel;
  }

  void unregister(Object? requestId) {
    if (requestId == null) return;
    _byRequestId.remove(_key(requestId));
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
