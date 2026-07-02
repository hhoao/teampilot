import '../jsonrpc.dart';
import '../toolkit/mcp_schema.dart';
import '../toolkit/teammate_bus_tool.dart';
import '../toolkit/teammate_bus_tool_call.dart';
import '../toolkit/teammate_bus_tool_format.dart';
import '../toolkit/teammate_bus_tool_name.dart';

final class ListTeammatesTool extends TeammateBusTool {
  const ListTeammatesTool();

  @override
  TeammateBusToolName get name => TeammateBusToolName.listTeammates;

  @override
  String get description =>
      'List all team members and team config (Claude-style roster): ids, '
      'agentId, agentType, model, provider, CLI, taskId, cwd, prompt '
      'summary, plus live bus state (unread, wait_for_message, pty). '
      'Use member id in send_message(to=...).';

  @override
  Map<String, Object?> get inputSchema => McpSchema.object();

  @override
  Future<JsonRpcResponse> call(TeammateBusToolCall call) async => call.ok(
        TeammateBusToolFormat.encodeRoster(call.bus, call.memberId),
      );
}
