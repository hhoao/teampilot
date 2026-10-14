import '../../agent_status/agent_permission_request.dart';
import 'mcp/teammate_bus_mcp_config.dart';

/// Whether an ACP/chat permission card is for TeamPilot's own teammate-bus MCP.
///
/// Cursor ACP titles these `teammate-bus-<tool>: <tool>` (e.g.
/// `teammate-bus-read_messages: read_messages`). The bus is host-installed
/// infrastructure, not a user-facing tool to approve.
bool isTeammateBusPermissionRequest(AgentPermissionRequest request) {
  return isTeammateBusPermissionText(request.description) ||
      request.patterns.any(isTeammateBusPermissionText);
}

/// Whether [text] names TeamPilot's teammate-bus MCP server.
bool isTeammateBusPermissionText(String text) {
  return text.toLowerCase().contains(teammateBusMcpServerName);
}

/// Whether an ACP tool-call payload is for the host teammate-bus MCP.
///
/// Matches [title], [rawInput], and [meta] against the bus server name
/// (`teammate-bus`). Bare tool names such as `read_messages` do not match.
bool isTeammateBusToolCall({String? title, Object? rawInput, Object? meta}) {
  return _mentionsBusValue(title) ||
      _mentionsBusValue(rawInput) ||
      _mentionsBusValue(meta);
}

bool _mentionsBusValue(Object? value) {
  if (value == null) return false;
  if (value is String) return isTeammateBusPermissionText(value);
  if (value is Map) {
    for (final entry in value.entries) {
      if (_mentionsBusValue(entry.key) || _mentionsBusValue(entry.value)) {
        return true;
      }
    }
    return false;
  }
  if (value is Iterable) {
    return value.any(_mentionsBusValue);
  }
  return isTeammateBusPermissionText(value.toString());
}
