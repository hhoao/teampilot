import 'mcp_schema.dart';
import 'mcp_tool_def.dart';
import 'teammate_bus_tool_name.dart';

abstract final class ListTeammatesTool {
  static final def = McpToolDef(
    name: TeammateBusToolName.listTeammates,
    description:
        'List all team members and team config (Claude-style roster): ids, '
        'agentId, agentType, model, provider, CLI, taskId, cwd, prompt '
        'summary, plus live bus state (unread, wait_for_message, pty). '
        'Use member id in send_message(to=...).',
    inputSchema: McpSchema.object(),
  );
}
