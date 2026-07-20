import '../../models/runtime_target.dart';
import '../team_bus/mcp/teammate_bus_mcp_gateway.dart';
import '../team_bus/remote/member_bus_mcp_config.dart';
import 'member_agent_status_endpoint.dart';

/// Whether this SSH seat needs a status-only HTTP reverse tunnel.
///
/// Mixed seats already open an idle/MCP tunnel ([remoteBinding] non-null).
/// Local / WSL seats stamp the app-host gateway URL — no reverse tunnel.
bool needsAgentStatusOnlyHttpTunnel({
  required RuntimeKind launchKind,
  required RemoteBusBinding? mixedRemoteBinding,
}) =>
    launchKind == RuntimeKind.ssh && mixedRemoteBinding == null;

/// Pick the stamped agent-status endpoint once any SSH tunnel (or null) is known.
///
/// [remoteBinding] covers mixed idle tunnels and status-only [bindHttpMember]
/// results. Never pass an app-host local URL for a remote agent process.
MemberAgentStatusEndpoint resolveMemberAgentStatusEndpoint({
  required TeammateBusMcpGateway gateway,
  required String sessionId,
  RemoteBusBinding? remoteBinding,
}) {
  if (remoteBinding != null) {
    return MemberAgentStatusEndpoint.remote(remoteBinding);
  }
  return MemberAgentStatusEndpoint.local(gateway, sessionId: sessionId);
}
