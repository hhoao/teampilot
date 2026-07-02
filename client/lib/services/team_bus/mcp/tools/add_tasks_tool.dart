import 'mcp_schema.dart';
import 'mcp_tool_def.dart';
import 'teammate_bus_tool_name.dart';

abstract final class AddTasksTool {
  static const tasks = 'tasks';
  static const title = 'title';
  static const brief = 'brief';
  static const dependsOn = 'depends_on';
  static const requiredCapabilities = 'required_capabilities';
  static const preferredCapabilities = 'preferred_capabilities';
  static const preferredAssignee = 'preferred_assignee';

  static final _taskItemSchema = {
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      title: McpSchema.string,
      brief: McpSchema.string,
      dependsOn: McpSchema.array(items: McpSchema.string),
      requiredCapabilities: McpSchema.array(items: McpSchema.string),
      preferredCapabilities: McpSchema.array(items: McpSchema.string),
      preferredAssignee: McpSchema.string,
    },
    'required': [title, brief],
  };

  static final def = McpToolDef(
    name: TeammateBusToolName.addTasks,
    description:
        'Leader: enqueue tasks onto the shared work queue. Idle workers '
        'receive them automatically via their own wait_for_message (FIFO, '
        'deps-gated, auto-claimed). Each task: title (one line), brief (full '
        'instructions), optional depends_on (task ids that must be done '
        'first). Optionally route by capability: required_capabilities (hard '
        'filter — only members with all of them claim it), '
        'preferred_capabilities (ranking among eligible), and '
        'preferred_assignee (member id given first dibs).',
    inputSchema: McpSchema.object(
      properties: {
        tasks: McpSchema.array(items: _taskItemSchema),
      },
      required: [tasks],
    ),
  );
}
