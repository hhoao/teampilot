import '../../tasks/team_task.dart';
import '../jsonrpc.dart';
import '../toolkit/mcp_schema.dart';
import '../toolkit/teammate_bus_tool.dart';
import '../toolkit/teammate_bus_tool_call.dart';
import '../toolkit/teammate_bus_tool_context.dart';
import '../toolkit/teammate_bus_tool_name.dart';

final class UpdateTaskTool extends TeammateBusTool {
  const UpdateTaskTool();

  static const taskId = 'task_id';
  static const status = 'status';
  static const result = 'result';

  @override
  TeammateBusToolName get name => TeammateBusToolName.updateTask;

  @override
  bool isEnabled(TeammateBusToolContext ctx) => ctx.bus.hasTaskQueue;

  @override
  String get description =>
      'Worker: report a claimed task as done | failed | cancelled, with an '
      'optional result note (findings, file paths, failure reason). Only '
      'the claiming worker may update its task.';

  @override
  Map<String, Object?> get inputSchema => McpSchema.object(
    properties: {
      taskId: McpSchema.string,
      status: McpSchema.stringEnum(['done', 'failed', 'cancelled']),
      result: McpSchema.string,
    },
    required: [taskId, status],
  );

  @override
  Future<JsonRpcResponse> call(TeammateBusToolCall call) async {
    final unavailable = call.taskQueueUnavailable();
    if (unavailable != null) return unavailable;

    final taskId = call.argString(UpdateTaskTool.taskId)?.trim() ?? '';
    final status = TaskStatus.parse(call.argString(UpdateTaskTool.status));
    if (!status.isTerminal) {
      return call.ok('Invalid status. Use done | failed | cancelled.');
    }
    final ok = call.bus.updateTask(
      taskId,
      status,
      result: call.argString(UpdateTaskTool.result),
      byMember: call.memberId,
    );
    return call.ok(
      ok
          ? 'Task $taskId -> ${status.name}.'
          : 'Update rejected (unknown task or not the claiming worker): $taskId',
    );
  }
}
