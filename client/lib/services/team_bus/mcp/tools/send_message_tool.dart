import 'mcp_schema.dart';
import 'mcp_tool_def.dart';
import 'teammate_bus_tool_name.dart';

abstract final class SendMessageTool {
  static const to = 'to';
  static const content = 'content';

  static final def = McpToolDef(
    name: TeammateBusToolName.sendMessage,
    description:
        'Send a message to a teammate by member id or agentId '
        '(e.g. developer or developer@team-1), or "*" to broadcast.',
    inputSchema: McpSchema.object(
      properties: {
        to: McpSchema.string,
        content: McpSchema.string,
      },
      required: [to, content],
    ),
  );
}
