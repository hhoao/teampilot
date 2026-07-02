import 'mcp_schema.dart';
import 'mcp_tool_def.dart';
import 'teammate_bus_tool_name.dart';

abstract final class ListTasksTool {
  static const status = 'status';

  static final def = McpToolDef(
    name: TeammateBusToolName.listTasks,
    description:
        'List the shared work queue (board). Optional status filter: '
        'pending | claimed | done | failed | cancelled.',
    inputSchema: McpSchema.object(
      properties: {status: McpSchema.string},
    ),
  );
}
