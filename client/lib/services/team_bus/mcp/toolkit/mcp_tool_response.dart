import '../jsonrpc.dart';
import '../mcp_method.dart';

/// MCP `tools/call` JSON-RPC response builders.
abstract final class McpToolResponse {
  static JsonRpcResponse ok(Object? id, String text) => JsonRpcResponse.result(id, {
        'content': [
          {'type': 'text', 'text': text},
        ],
        'isError': false,
      });

  static JsonRpcResponse toolError(Object? id, String text) =>
      JsonRpcResponse.result(id, {
        'content': [
          {'type': 'text', 'text': text},
        ],
        'isError': true,
      });

  static JsonRpcResponse invalidParams(Object? id, String message) =>
      JsonRpcResponse.error(id, JsonRpcErrorCode.invalidParams, message);
}
