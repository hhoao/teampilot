import '../jsonrpc.dart';
import '../toolkit/mcp_schema.dart';
import '../toolkit/teammate_bus_tool.dart';
import '../toolkit/teammate_bus_tool_call.dart';
import '../toolkit/teammate_bus_tool_context.dart';
import '../toolkit/teammate_bus_tool_format.dart';
import '../toolkit/teammate_bus_tool_name.dart';

final class ClaimTaskTool extends TeammateBusTool {
  const ClaimTaskTool();

  static const taskId = 'task_id';

  @override
  TeammateBusToolName get name => TeammateBusToolName.claimTask;

  @override
  bool isEnabled(TeammateBusToolContext ctx) => ctx.bus.hasTaskQueue;

  @override
  String get description =>
      'Worker: self-pick a specific task you are eligible for from the '
      'board (use list_tasks to see eligible_for_you/match_score). Claims '
      'it atomically; fails if it is gone, already claimed, blocked, or you '
      'are not eligible. On success returns the claimed task as JSON '
      '(id/status/title/brief). Do the work, then update_task, then call '
      'wait_for_message again.';

  @override
  Map<String, Object?> get inputSchema => McpSchema.object(
    properties: {taskId: McpSchema.string},
    required: [taskId],
  );

  @override
  Future<JsonRpcResponse> call(TeammateBusToolCall call) async {
    final unavailable = call.taskQueueUnavailable();
    if (unavailable != null) return unavailable;

    final taskId = call.argString(ClaimTaskTool.taskId)?.trim() ?? '';
    final claimed = call.bus.claimSpecificTask(taskId, call.memberId);
    if (claimed == null) {
      return call.toolError(
        'Could not claim "$taskId" (gone, already claimed, blocked, or you '
        'are not eligible).',
      );
    }
    return call.ok(TeammateBusToolFormat.encodeTaskAssignment(claimed));
  }
}
