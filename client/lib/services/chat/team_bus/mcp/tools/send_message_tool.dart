import '../jsonrpc.dart';
import '../../team_message.dart';
import '../toolkit/mcp_schema.dart';
import '../toolkit/teammate_bus_tool.dart';
import '../toolkit/teammate_bus_tool_call.dart';
import '../toolkit/teammate_bus_tool_format.dart';
import '../toolkit/teammate_bus_tool_name.dart';

final class SendMessageTool extends TeammateBusTool {
  const SendMessageTool();

  static const to = 'to';
  static const content = 'content';

  @override
  TeammateBusToolName get name => TeammateBusToolName.sendMessage;

  @override
  String get description =>
      'Send a message to a teammate by member id or agentId '
      '(e.g. developer or developer@team-1), or "*" to broadcast.';

  @override
  Map<String, Object?> get inputSchema => McpSchema.object(
    properties: {to: McpSchema.string, content: McpSchema.string},
    required: [to, content],
  );

  @override
  Future<JsonRpcResponse> call(TeammateBusToolCall call) async {
    final to = call.argString(SendMessageTool.to)?.trim() ?? '';
    final content = call.argString(SendMessageTool.content) ?? '';
    if (to.isEmpty) {
      return call.toolError('send_message requires a non-empty "to".');
    }
    final message = TeamMessage(
      id: call.ctx.idGenerator(),
      from: call.memberId,
      to: to,
      content: content,
    );
    if (to == '*') {
      await call.bus.broadcast(message, materializeDeclared: true);
      return call.ok('sent');
    }
    final outcome = await call.bus.send(message);
    if (!outcome.delivered) {
      return call.toolError(
        'Message not delivered (${outcome.reason}): recipient "$to" '
        'is not on the bus.\n${TeammateBusToolFormat.unknownRecipientHint(call.bus)}',
      );
    }
    final resolved = outcome.memberId!;
    if (resolved == to) {
      return call.ok('sent');
    }
    return call.ok('sent to $resolved (resolved from agentId "$to")');
  }
}
