import '../../io/filesystem.dart';
import '../../ssh/ssh_member_session.dart';
import '../mcp/teammate_bus_mcp_gateway.dart';
import '../mcp/teammate_bus_session_registry.dart';
import 'remote_bus_mount.dart';

/// Builds a [RemoteBusMount] for one remote member's dedicated SSH session plane.
RemoteBusMount buildRemoteBusMount({
  required SshMemberSession memberSession,
  required TeammateBusMcpGateway gateway,
  required TeammateBusSessionRegistration registration,
  required Filesystem storageFs,
  required String arch,
}) {
  return RemoteBusMount(
    httpBusPort: gateway.mcpEndpoint.port,
    rawSocketPort: gateway.rawSocketPort,
    memberSession: memberSession,
    storageFs: storageFs,
    arch: arch,
    token: registration.token,
  );
}
