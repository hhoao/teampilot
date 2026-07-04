import '../jsonrpc.dart';
import 'teammate_bus_tool_call.dart';
import 'teammate_bus_tool_context.dart';
import 'teammate_bus_tool_name.dart';

/// Teammate-bus MCP tool: advertisement (`tools/list`) + handler (`tools/call`).
abstract class TeammateBusTool {
  const TeammateBusTool();

  TeammateBusToolName get name;
  String get description;
  Map<String, Object?> get inputSchema;

  /// Gate tool advertisement and dispatch (task queue, artifacts, …).
  bool isEnabled(TeammateBusToolContext ctx) => true;

  Future<JsonRpcResponse> call(TeammateBusToolCall call);

  Map<String, Object?> toJson() => {
    'name': name.value,
    'description': description,
    'inputSchema': inputSchema,
  };
}
