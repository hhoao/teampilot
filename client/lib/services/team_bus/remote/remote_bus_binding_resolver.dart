import '../../../models/team_config.dart';
import '../../cli/registry/capabilities/bus_transport_capability.dart';
import '../../cli/registry/cli_tool_registry.dart';
import 'member_bus_mcp_config.dart';
import 'remote_bus_mount.dart';

/// Binds remote (ssh) members to an existing tab-owned [RemoteBusMount].
class RemoteBusBindingResolver {
  RemoteBusBindingResolver({CliToolRegistry? registry})
      : _registry = registry ?? CliToolRegistry.builtIn();

  final CliToolRegistry _registry;

  Future<RemoteBusBinding> bindMember({
    required RemoteBusMount mount,
    required String memberId,
    required CliTool cli,
  }) async {
    final longBlocking = _registry
            .capability<BusTransportCapability>(cli)
            ?.longBlockingWaitForMessage ??
        true;
    return longBlocking
        ? await mount.bindLongBlockingMember(memberId)
        : await mount.bindHttpMember(memberId);
  }
}
