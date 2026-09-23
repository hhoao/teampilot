import '../../../io/filesystem.dart';
import '../../../../models/team_config.dart';
import '../../../ssh/ssh_member_session.dart';
import '../../session/chat_tab.dart';
import '../mcp/teammate_bus_mcp_gateway_port.dart';
import 'member_bus_mcp_config.dart';
import 'remote_bus_binding_resolver.dart';
import 'ssh_remote_bus_mount_factory.dart';

export 'remote_bus_mount.dart' show archFromUname;

/// Reverse-tunnel mount + bind for one remote member seat.
abstract interface class RemoteMemberBusSetupPort {
  Future<RemoteBusBinding> mountAndBindMixed({
    required ChatTab tab,
    required String memberId,
    required CliTool cli,
    required SshMemberSession memberSession,
    required TeammateBusMcpGatewayPort gateway,
    required Filesystem storageFs,
    required String arch,
  });

  Future<RemoteBusBinding> mountAndBindStatusOnly({
    required ChatTab tab,
    required String memberId,
    required SshMemberSession memberSession,
    required TeammateBusMcpGatewayPort gateway,
    required Filesystem storageFs,
    required String arch,
    required String token,
  });
}

/// Production [RemoteMemberBusSetupPort]: tab-owned [RemoteBusMount] + resolver.
class RemoteMemberBusSetup implements RemoteMemberBusSetupPort {
  RemoteMemberBusSetup({RemoteBusBindingResolver? resolver})
    : _resolver = resolver ?? RemoteBusBindingResolver();

  final RemoteBusBindingResolver _resolver;

  @override
  Future<RemoteBusBinding> mountAndBindMixed({
    required ChatTab tab,
    required String memberId,
    required CliTool cli,
    required SshMemberSession memberSession,
    required TeammateBusMcpGatewayPort gateway,
    required Filesystem storageFs,
    required String arch,
  }) async {
    final registration = tab.busSessionRegistration;
    if (registration == null) {
      throw StateError('mixed bus session is not registered');
    }
    final mount = buildRemoteBusMount(
      memberSession: memberSession,
      gateway: gateway,
      registration: registration,
      storageFs: storageFs,
      arch: arch,
    );
    tab.memberRemoteBusMounts[memberId] = mount;
    return _resolver.bindMember(mount: mount, memberId: memberId, cli: cli);
  }

  @override
  Future<RemoteBusBinding> mountAndBindStatusOnly({
    required ChatTab tab,
    required String memberId,
    required SshMemberSession memberSession,
    required TeammateBusMcpGatewayPort gateway,
    required Filesystem storageFs,
    required String arch,
    required String token,
  }) async {
    final mount = buildStatusOnlyRemoteBusMount(
      memberSession: memberSession,
      gateway: gateway,
      storageFs: storageFs,
      arch: arch,
      token: token,
    );
    tab.memberRemoteBusMounts[memberId] = mount;
    return mount.bindHttpMember(memberId);
  }
}
