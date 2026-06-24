import '../../../models/runtime_target.dart';
import '../../../models/team_config.dart';
import '../../cli/registry/capabilities/bus_transport_capability.dart';
import '../../cli/registry/cli_tool_registry.dart';
import '../mcp/teammate_bus_mcp_server.dart';
import 'member_bus_mcp_config.dart';
import 'remote_bus_mount.dart';

/// Builds a fully-configured [RemoteBusMount] for a remote (ssh) member target.
/// Production builds one over a real `SshReverseTunnel`; tests inject one over a
/// `FakeReverseTunnel` — so the call-site wiring is exercised without real SSH.
typedef RemoteBusMountFactory = Future<RemoteBusMount> Function({
  required RuntimeTarget memberTarget,
  required TeammateBusMcpServer busServer,
});

/// Outcome of [RemoteBusBindingResolver.resolve]: the per-tab [mount] (to store
/// on the tab and tear down on close) plus the member's [binding].
typedef RemoteBusResolution = ({RemoteBusMount mount, RemoteBusBinding binding});

/// The launch path's seam (#1) for connecting a **remote** member back to the
/// in-process bus over a reverse tunnel. Local members resolve to `null` (the
/// caller keeps the existing local transport).
///
/// Stateless: the per-tab [RemoteBusMount] is owned by the caller (stored on the
/// tab, closed in its dispose path); [resolve] reuses an [existingMount] when one
/// is passed. DI: the mount is built by [mountFactory], so a `FakeReverseTunnel`
/// -backed factory drives this end-to-end in unit tests — only the real
/// `SshReverseTunnel.open()` against a live SSH host stays on-device.
class RemoteBusBindingResolver {
  RemoteBusBindingResolver({
    required this.mountFactory,
    CliToolRegistry? registry,
  }) : _registry = registry ?? CliToolRegistry.builtIn();

  final RemoteBusMountFactory mountFactory;
  final CliToolRegistry _registry;

  /// Resolves the binding for [memberId] on [memberTarget]. Returns `null` for a
  /// non-ssh (local/home) member. Long-blocking CLIs get a relay-over-tunnel
  /// binding; cursor (doorbell) gets HTTP-over-tunnel. Pass the tab's
  /// [existingMount] to reuse it across reconnects / multiple members.
  Future<RemoteBusResolution?> resolve({
    required RemoteBusMount? existingMount,
    required RuntimeTarget memberTarget,
    required String memberId,
    required CliTool cli,
    required TeammateBusMcpServer busServer,
  }) async {
    if (memberTarget.kind != RuntimeKind.ssh) return null;
    final mount = existingMount ??
        await mountFactory(memberTarget: memberTarget, busServer: busServer);
    final longBlocking = _registry
            .capability<BusTransportCapability>(cli)
            ?.longBlockingWaitForMessage ??
        true;
    final binding = longBlocking
        ? await mount.bindLongBlockingMember(memberId)
        : await mount.bindHttpMember(memberId);
    return (mount: mount, binding: binding);
  }
}
