import 'dart:async';
import 'dart:math';

import '../../../models/runtime_target.dart';
import '../../io/filesystem.dart';
import '../../ssh/ssh_member_session.dart';
import 'member_bus_mcp_config.dart';
import 'relay_provisioner.dart';
import 'reverse_tunnel.dart';

/// Per-tab mount that connects **remote** (ssh) members back to the local,
/// in-process teammate bus over an SSH reverse tunnel (P3b).
///
/// Owns per-member reverse tunnels only. The SSH session plane lives in
/// [memberSession] and is closed by the tab when the member disconnects — not
/// by [close].
///
/// Transport split:
/// - **Long-blocking MCP** (claude/codex/…) → raw-socket tunnel to gateway
///   [rawSocketPort] + relay argv.
/// - **HTTP surfaces** (cursor MCP, all `/idle` Stop hooks) → HTTP tunnel to
///   gateway [httpBusPort]; token validated by the gateway registry.
class RemoteBusMount {
  RemoteBusMount({
    required this.httpBusPort,
    required this.rawSocketPort,
    required SshMemberSession memberSession,
    required this.storageFs,
    required this.arch,
    this.remoteOs = RemoteOs.posix,
    this.relayProvisioner = const RelayProvisioner(),
    ReverseTunnel Function()? tunnelFactory,
    String? token,
  }) : memberSession = memberSession,
       token = token ?? _randomToken(),
       _tunnelFactory = tunnelFactory ?? memberSession.newReverseTunnel,
       _remoteRun = null;

  /// Test / harness constructor without a live [SshMemberSession].
  RemoteBusMount.testing({
    required this.httpBusPort,
    required this.rawSocketPort,
    required this.storageFs,
    required this.arch,
    required RemoteCommandRunner remoteRun,
    required ReverseTunnel Function() tunnelFactory,
    this.remoteOs = RemoteOs.posix,
    this.relayProvisioner = const RelayProvisioner(),
    String? token,
  }) : token = token ?? _randomToken(),
       memberSession = null,
       _tunnelFactory = tunnelFactory,
       _remoteRun = remoteRun;

  final int httpBusPort;
  final int rawSocketPort;
  final SshMemberSession? memberSession;
  final Filesystem storageFs;
  final String arch;
  final RemoteOs remoteOs;
  final RelayProvisioner relayProvisioner;
  final String token;

  final ReverseTunnel Function() _tunnelFactory;
  final RemoteCommandRunner? _remoteRun;

  RemoteCommandRunner get _run {
    final run = _remoteRun;
    if (run != null) return run;
    final session = memberSession;
    if (session == null) {
      throw StateError('RemoteBusMount has no SSH member session');
    }
    return session.run;
  }

  final _members = <String, _MountedMember>{};
  final _preparedRelay = <String, PreparedRelay>{};

  Future<RemoteBusBinding> bindLongBlockingMember(String memberId) async {
    final existing = _members[memberId];
    if (existing != null) return existing.binding;

    final prepared = _preparedRelay[memberId] ??= await relayProvisioner
        .prepare(
          remoteFs: storageFs,
          run: _run,
          arch: arch,
          remoteOs: remoteOs,
        );

    final mcpTunnel = _tunnelFactory();
    final idleTunnel = _tunnelFactory();
    TunnelPump? mcpPump;
    TunnelPump? idlePump;
    var mcpPumpStarted = false;
    var idlePumpStarted = false;
    try {
      final mcpRawTunnelPort = await mcpTunnel.open();
      final idleHttpTunnelPort = await idleTunnel.open();

      mcpPump = TunnelPump(tunnel: mcpTunnel, localPort: rawSocketPort);
      await mcpPump.start();
      mcpPumpStarted = true;

      idlePump = TunnelPump(tunnel: idleTunnel, localPort: httpBusPort);
      await idlePump.start();
      idlePumpStarted = true;

      final plan = relayProvisioner.planFor(
        prepared: prepared,
        tunnelPort: mcpRawTunnelPort,
        token: token,
        memberId: memberId,
      );

      final binding = RemoteBusBinding(
        token: token,
        idleHttpTunnelPort: idleHttpTunnelPort,
        mcpRawTunnelPort: mcpRawTunnelPort,
        mcpRelayArgv: plan.argv,
      );
      _members[memberId] = _MountedMember(
        binding: binding,
        tunnels: [
          (tunnel: mcpTunnel, pump: mcpPump),
          (tunnel: idleTunnel, pump: idlePump),
        ],
      );
      return binding;
    } on Object {
      if (idlePumpStarted) {
        await idlePump!.stop();
      } else {
        await idleTunnel.close();
      }
      if (mcpPumpStarted) {
        await mcpPump!.stop();
      } else {
        await mcpTunnel.close();
      }
      rethrow;
    }
  }

  Future<RemoteBusBinding> bindHttpMember(String memberId) async {
    final existing = _members[memberId];
    if (existing != null) return existing.binding;

    final tunnel = _tunnelFactory();
    TunnelPump? pump;
    var pumpStarted = false;
    try {
      final port = await tunnel.open();
      pump = TunnelPump(tunnel: tunnel, localPort: httpBusPort);
      await pump.start();
      pumpStarted = true;

      final binding = RemoteBusBinding(
        token: token,
        idleHttpTunnelPort: port,
        mcpHttpTunnelPort: port,
      );
      _members[memberId] = _MountedMember(
        binding: binding,
        tunnels: [(tunnel: tunnel, pump: pump)],
      );
      return binding;
    } on Object {
      if (pumpStarted) {
        await pump!.stop();
      } else {
        await tunnel.close();
      }
      rethrow;
    }
  }

  /// Tears down tunnels. Does not close [memberSession].
  Future<void> close() async {
    for (final m in _members.values) {
      for (final t in m.tunnels) {
        await t.pump.stop();
      }
    }
    _members.clear();
    _preparedRelay.clear();
  }

  static String _randomToken() {
    final rng = Random.secure();
    return List.generate(24, (_) => rng.nextInt(16).toRadixString(16)).join();
  }
}

class _MountedMember {
  _MountedMember({required this.binding, required this.tunnels});

  final RemoteBusBinding binding;
  final List<({ReverseTunnel tunnel, TunnelPump pump})> tunnels;
}

String archFromUname(String unameM) {
  final m = unameM.trim().toLowerCase();
  return switch (m) {
    'x86_64' || 'amd64' => 'linux-x64',
    'aarch64' || 'arm64' => 'linux-arm64',
    _ => m,
  };
}
