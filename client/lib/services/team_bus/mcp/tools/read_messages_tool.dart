import 'mcp_schema.dart';
import 'mcp_tool_def.dart';
import 'teammate_bus_tool_name.dart';

abstract final class ReadMessagesTool {
  static const afterId = 'after_id';
  static const limit = 'limit';
  static const unreadOnly = 'unread_only';
  static const markRead = 'mark_read';

  static final def = McpToolDef(
    name: TeammateBusToolName.readMessages,
    description:
        'Page through persisted mailbox (unread by default) WITHOUT consuming. '
        'Use after_id from the previous page for pagination. Set '
        'mark_read=true to consume the returned page (mark read + drop from '
        'the wait_for_message queue) instead of blocking in wait_for_message.',
    inputSchema: McpSchema.object(
      properties: {
        afterId: McpSchema.string,
        limit: McpSchema.integer(minimum: 1, maximum: 100),
        unreadOnly: McpSchema.boolean,
        markRead: McpSchema.boolean,
      },
    ),
  );
}
