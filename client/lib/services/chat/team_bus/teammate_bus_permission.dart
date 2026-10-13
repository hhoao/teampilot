import '../../agent_status/agent_permission_request.dart';
import 'mcp/teammate_bus_mcp_config.dart';
import 'mcp/toolkit/teammate_bus_tool_name.dart';

/// Whether an ACP/chat permission card is for TeamPilot's own teammate-bus MCP.
///
/// Cursor ACP titles these `teammate-bus-<tool>: <tool>` (e.g.
/// `teammate-bus-read_messages: read_messages`). The bus is host-installed
/// infrastructure, not a user-facing tool to approve.
bool isTeammateBusPermissionRequest(AgentPermissionRequest request) {
  return isTeammateBusPermissionText(
    '${request.description} ${request.patterns.join(' ')}',
  );
}

/// Same host-MCP check from a raw ACP tool-call title / input / meta haystack.
bool isTeammateBusToolCall({
  String? title,
  Object? rawInput,
  Map<String, Object?>? meta,
}) {
  return isTeammateBusPermissionText(
    [
      title ?? '',
      _stringify(rawInput),
      if (meta != null) _stringify(meta),
    ].join(' '),
  );
}

bool isTeammateBusPermissionText(String text) {
  final haystack = text.toLowerCase();
  if (haystack.contains(teammateBusMcpServerName)) return true;
  for (final tool in TeammateBusToolName.values) {
    if (haystack.contains(tool.value)) return true;
  }
  return false;
}

String _stringify(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}
