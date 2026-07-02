import '../jsonrpc.dart';
import '../toolkit/mcp_schema.dart';
import '../toolkit/teammate_bus_tool.dart';
import '../toolkit/teammate_bus_tool_call.dart';
import '../toolkit/teammate_bus_tool_format.dart';
import '../toolkit/teammate_bus_tool_name.dart';

final class ReadMessagesTool extends TeammateBusTool {
  const ReadMessagesTool();

  static const afterId = 'after_id';
  static const limit = 'limit';
  static const unreadOnly = 'unread_only';
  static const markRead = 'mark_read';

  @override
  TeammateBusToolName get name => TeammateBusToolName.readMessages;

  @override
  String get description =>
      'Page through persisted mailbox (unread by default) WITHOUT consuming. '
      'Use after_id from the previous page for pagination. Set '
      'mark_read=true to consume the returned page (mark read + drop from '
      'the wait_for_message queue) instead of blocking in wait_for_message.';

  @override
  Map<String, Object?> get inputSchema => McpSchema.object(
        properties: {
          afterId: McpSchema.string,
          limit: McpSchema.integer(minimum: 1, maximum: 100),
          unreadOnly: McpSchema.boolean,
          markRead: McpSchema.boolean,
        },
      );

  @override
  Future<JsonRpcResponse> call(TeammateBusToolCall call) async {
    final afterId = call.argString(ReadMessagesTool.afterId)?.trim();
    final limit = call.argInt(ReadMessagesTool.limit) ?? 20;
    final unreadOnly =
        call.argBool(ReadMessagesTool.unreadOnly, defaultValue: true);
    // 默认浏览不消费（与工具描述一致）；wait_for_message 才是消费路径。
    final markRead =
        call.argBool(ReadMessagesTool.markRead, defaultValue: false);
    final page = await call.bus.readMessages(
      call.memberId,
      afterId: afterId?.isEmpty == true ? null : afterId,
      limit: limit,
      unreadOnly: unreadOnly,
      markRead: markRead,
    );
    return call.ok(TeammateBusToolFormat.encodeMessagePage(page));
  }
}
