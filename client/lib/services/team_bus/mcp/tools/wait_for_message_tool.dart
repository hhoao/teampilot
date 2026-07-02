import 'mcp_schema.dart';
import 'mcp_tool_def.dart';
import 'teammate_bus_tool_name.dart';

abstract final class WaitForMessageTool {
  static final def = McpToolDef(
    name: TeammateBusToolName.waitForMessage,
    description:
        'Your single idle loop. Blocks indefinitely until there is something '
        'to do, then returns ONE of: (a) a batch of teammate/operator '
        'messages, or (b) a TASK already claimed for you from the shared '
        'work queue. If it returns a task, do it and report via update_task; '
        'if messages, handle them. Either way, call wait_for_message again '
        'afterwards. User input while you wait appears as FROM user '
        '(operator):. (Team leads only ever receive messages here.)',
    inputSchema: McpSchema.object(),
  );
}
