import 'mcp_schema.dart';
import 'mcp_tool_def.dart';
import 'teammate_bus_tool_name.dart';

abstract final class UpdateTaskTool {
  static const taskId = 'task_id';
  static const status = 'status';
  static const result = 'result';

  static final def = McpToolDef(
    name: TeammateBusToolName.updateTask,
    description:
        'Worker: report a claimed task as done | failed | cancelled, with an '
        'optional result note (findings, file paths, failure reason). Only '
        'the claiming worker may update its task.',
    inputSchema: McpSchema.object(
      properties: {
        taskId: McpSchema.string,
        status: McpSchema.stringEnum(['done', 'failed', 'cancelled']),
        result: McpSchema.string,
      },
      required: [taskId, status],
    ),
  );
}
