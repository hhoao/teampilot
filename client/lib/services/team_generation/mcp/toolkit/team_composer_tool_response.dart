import 'dart:convert';

/// Handler result: a JSON-RPC-ready payload plus an optional post-flush
/// callback that the gateway runs only after the response bytes are written
/// and the connection closed.
final class TeamComposerMcpResult {
  const TeamComposerMcpResult({
    required this.response,
    this.afterResponseFlushed,
  });

  final Map<String, Object?> response;
  final Future<void> Function()? afterResponseFlushed;
}

/// MCP `tools/call` response builders for Team Composer (structured payloads).
abstract final class TeamComposerToolResponse {
  static TeamComposerMcpResult ok(
    Object? requestId,
    Map<String, Object?> data, {
    Future<void> Function()? afterResponseFlushed,
  }) {
    return TeamComposerMcpResult(
      response: {
        'jsonrpc': '2.0',
        'id': requestId,
        'result': {
          'content': [
            {
              'type': 'text',
              'text': jsonEncode(data),
            },
          ],
          'structuredContent': data,
        },
      },
      afterResponseFlushed: afterResponseFlushed,
    );
  }

  static TeamComposerMcpResult error(Object? requestId, String code) {
    return TeamComposerMcpResult(
      response: {
        'jsonrpc': '2.0',
        'id': requestId,
        'result': {
          'content': [
            {
              'type': 'text',
              'text': 'code=$code',
            },
          ],
          'isError': true,
          'structuredContent': {'code': code},
        },
      },
    );
  }
}
