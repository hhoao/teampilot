import 'mcp_schema.dart';
import 'mcp_tool_def.dart';
import 'teammate_bus_tool_name.dart';

abstract final class ClaimTaskTool {
  static const taskId = 'task_id';

  static final def = McpToolDef(
    name: TeammateBusToolName.claimTask,
    description:
        'Worker: self-pick a specific task you are eligible for from the '
        'board (use list_tasks to see eligible_for_you/match_score). Claims '
        'it atomically; fails if it is gone, already claimed, blocked, or you '
        'are not eligible.',
    inputSchema: McpSchema.object(
      properties: {taskId: McpSchema.string},
      required: [taskId],
    ),
  );
}
