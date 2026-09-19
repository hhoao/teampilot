/// MCP / JSON-RPC method names handled by [TeammateBusMcpHandler].
abstract final class McpMethod {
  static const initialize = 'initialize';
  static const notificationsInitialized = 'notifications/initialized';
  static const notificationsProgress = 'notifications/progress';
  static const notificationsCancelled = 'notifications/cancelled';
  static const ping = 'ping';
  static const toolsList = 'tools/list';
  static const toolsCall = 'tools/call';
}

/// JSON-RPC 2.0 error codes used by the teammate-bus MCP server.
abstract final class JsonRpcErrorCode {
  static const serverError = -32000;
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
}

/// Common JSON-RPC request `params` keys.
abstract final class McpParams {
  static const toolName = 'name';
  static const arguments = 'arguments';
  static const requestId = 'requestId';
  static const requestIdSnake = 'request_id';
}
