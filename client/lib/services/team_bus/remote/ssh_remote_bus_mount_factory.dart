import '../../../models/runtime_target.dart';
import '../../io/filesystem.dart';
import '../../ssh/ssh_member_session.dart';
import '../mcp/teammate_bus_mcp_server.dart';
import 'remote_bus_mount.dart';

/// Builds a [RemoteBusMount] for one remote member's dedicated SSH session plane.
RemoteBusMount buildRemoteBusMount({
  required SshMemberSession memberSession,
  required TeammateBusMcpServer busServer,
  required Filesystem storageFs,
  required String arch,
}) {
  return RemoteBusMount(
    handler: busServer.handler,
    httpBusPort: busServer.port,
    memberSession: memberSession,
    storageFs: storageFs,
    arch: arch,
  );
}
