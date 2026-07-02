import 'dart:convert';

import 'mcp_method.dart';
import 'tools/teammate_bus_tool_name.dart';

/// 解析后的 JSON-RPC 2.0 请求/通知。
class JsonRpcRequest {
  const JsonRpcRequest({
    required this.method,
    this.id,
    this.params = const {},
  });

  final Object? id; // null = 通知（无响应）
  final String method;
  final Map<String, Object?> params;

  bool get isNotification => id == null;

  static JsonRpcRequest? tryParse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final method = decoded['method'];
    if (method is! String) return null;
    final rawParams = decoded['params'];
    return JsonRpcRequest(
      id: decoded['id'],
      method: method,
      params: rawParams is Map
          ? Map<String, Object?>.from(rawParams)
          : const {},
    );
  }
}

extension TeammateBusToolCallRequest on JsonRpcRequest {
  TeammateBusToolName? get toolName => method == McpMethod.toolsCall
      ? TeammateBusToolName.tryParse(params[McpParams.toolName] as String?)
      : null;

  Map<String, Object?> get toolArguments => params[McpParams.arguments] is Map
      ? Map<String, Object?>.from(params[McpParams.arguments] as Map)
      : const <String, Object?>{};
}

/// JSON-RPC 响应（成功或错误）。
class JsonRpcResponse {
  const JsonRpcResponse.result(this.id, this.result)
    : error = null,
      code = null;
  const JsonRpcResponse.error(this.id, this.code, this.error)
    : result = null;

  final Object? id;
  final Map<String, Object?>? result;
  final int? code;
  final String? error;

  Map<String, Object?> toJson() => {
    'jsonrpc': '2.0',
    'id': id,
    if (error == null) 'result': result else 'error': {
      'code': code,
      'message': error,
    },
  };

  String encode() => jsonEncode(toJson());
}
