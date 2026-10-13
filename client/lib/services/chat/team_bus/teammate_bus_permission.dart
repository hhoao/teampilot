import '../../agent_status/agent_permission_request.dart';
import 'mcp/teammate_bus_mcp_config.dart';

/// Whether an ACP/chat permission card is for TeamPilot's own teammate-bus MCP.
///
/// Cursor ACP titles these `teammate-bus-<tool>: <tool>` (e.g.
/// `teammate-bus-read_messages: read_messages`). The bus is host-installed
/// infrastructure, not a user-facing tool to approve.
bool isTeammateBusPermissionRequest(AgentPermissionRequest request) {
  return _mentionsBus(request.description) ||
      request.patterns.any(_mentionsBus);
}

bool _mentionsBus(String text) {
  return text.toLowerCase().contains(teammateBusMcpServerName);
}
