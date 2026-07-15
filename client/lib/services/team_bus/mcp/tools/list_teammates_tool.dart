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
      'List team members and team config as JSON: member_id, display_name, '
      'agent_id, agent_type, model, provider, cli, task_id, machine / '
      'machine_kind / machine_id, cwd, responsibilities, plus live bus state '
      '(unread, phase, pty_running). Use member_id in send_message(to=...).';

  @override
  Map<String, Object?> get inputSchema => McpSchema.object();

  @override
  Future<JsonRpcResponse> call(TeammateBusToolCall call) async =>
      call.ok(TeammateBusToolFormat.encodeRoster(call.bus, call.memberId));
}
