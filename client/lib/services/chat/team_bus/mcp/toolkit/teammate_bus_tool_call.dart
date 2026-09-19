import '../../artifacts/artifact_transfer_service.dart';
import '../../team_bus.dart';
import '../jsonrpc.dart';
import 'mcp_tool_response.dart';
import 'teammate_bus_tool_context.dart';

/// One `tools/call` invocation passed to a [TeammateBusTool] handler.
class TeammateBusToolCall {
  const TeammateBusToolCall({
    required this.ctx,
    required this.memberId,
    required this.requestId,
    required this.arguments,
  });

  final TeammateBusToolContext ctx;
  final String memberId;
  final Object? requestId;
  final Map<String, Object?> arguments;

  TeamBus get bus => ctx.bus;

  JsonRpcResponse ok(String text) => McpToolResponse.ok(requestId, text);

  JsonRpcResponse toolError(String text) =>
      McpToolResponse.toolError(requestId, text);

  JsonRpcResponse invalidParams(String message) =>
      McpToolResponse.invalidParams(requestId, message);

  /// Returns a response when the task queue is unavailable; null = proceed.
  JsonRpcResponse? taskQueueUnavailable() {
    if (bus.hasTaskQueue) return null;
    return invalidParams('No task queue');
  }

  /// Returns a response when artifact transfer is unavailable; null = proceed.
  JsonRpcResponse? artifactsUnavailable() {
    if (ctx.artifacts != null) return null;
    return invalidParams('No artifact transfer');
  }

  ArtifactTransferService get artifacts => ctx.artifacts!;

  String? argString(String key) => arguments[key] as String?;

  bool argBool(String key, {required bool defaultValue}) =>
      arguments[key] as bool? ?? defaultValue;

  int? argInt(String key) => (arguments[key] as num?)?.toInt();
}
