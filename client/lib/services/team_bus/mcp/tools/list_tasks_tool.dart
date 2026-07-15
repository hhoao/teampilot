import '../../tasks/team_task.dart';
import '../jsonrpc.dart';
import '../toolkit/mcp_schema.dart';
import '../toolkit/teammate_bus_tool.dart';
import '../toolkit/teammate_bus_tool_call.dart';
import '../toolkit/teammate_bus_tool_context.dart';
import '../toolkit/teammate_bus_tool_format.dart';
import '../toolkit/teammate_bus_tool_name.dart';

final class ListTasksTool extends TeammateBusTool {
  const ListTasksTool();

  static const status = 'status';

  @override
  TeammateBusToolName get name => TeammateBusToolName.listTasks;

  @override
  bool isEnabled(TeammateBusToolContext ctx) => ctx.bus.hasTaskQueue;

  @override
  String get description =>
      'List the shared work queue (board) as JSON {"tasks":[...]}. Optional '
      'status filter: pending | claimed | done | failed | cancelled.';

  @override
  Map<String, Object?> get inputSchema =>
      McpSchema.object(properties: {status: McpSchema.string});

  @override
  Future<JsonRpcResponse> call(TeammateBusToolCall call) async {
    final unavailable = call.taskQueueUnavailable();
    if (unavailable != null) return unavailable;

    final filter = call.argString(ListTasksTool.status)?.trim();
    final status = (filter == null || filter.isEmpty)
        ? null
        : TaskStatus.parse(filter);
    return call.ok(
      TeammateBusToolFormat.encodeTasks(
        call.bus,
        call.bus.listTasks(status: status),
        call.memberId,
      ),
    );
  }
}
