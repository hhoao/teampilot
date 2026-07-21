import '../core/turns.dart';

/// Pluggable HTTP/SSE mapping for one model wire protocol.
///
/// Task 5's server routes by [matchesPath], calls [resolveInboundTurn], then
/// [encodeResponse]. Keep adapters free of HTTP server concerns.
abstract interface class WireAdapter {
  /// Short id for request logs (e.g. `anthropic`, `openai_chat`).
  String get wireId;

  /// Whether this adapter handles [path] (e.g. `/v1/messages`).
  bool matchesPath(String path);

  /// MIME type for [encodeResponse] bodies.
  String get responseMimeType;

  /// Encode [turn] as the HTTP response body for this wire.
  String encodeResponse({
    required ResolvedTurn turn,
    required String messageId,
    required String model,
  });

  /// Resolve inbound-dependent turns (e.g. AssignedTaskUpdate task id).
  ///
  /// Returns [turn] unchanged when no resolution is needed.
  ResolvedTurn resolveInboundTurn(
    ResolvedTurn turn,
    Map<String, Object?>? requestBody,
  );
}
