import 'dart:async';
import 'dart:math';

import '../../../models/runtime_target.dart';
import '../../io/filesystem.dart';
import '../../ssh/ssh_member_session.dart';
import '../mcp/teammate_bus_mcp_handler.dart';
import 'bus_http_token_guard.dart';
import 'bus_raw_socket_server.dart';
import 'member_bus_mcp_config.dart';
import 'relay_provisioner.dart';
import 'reverse_tunnel.dart';

/// Per-tab mount that connects **remote** (ssh) members back to the local,
/// in-process teammate bus over an SSH reverse tunnel (P3b).
///
/// Owns bus-side resources (raw socket / HTTP guard, per-member tunnels). The
/// SSH session plane lives in [memberSession] and is closed by the tab when the
/// member disconnects — not by [close].
class RemoteBusMount {
  RemoteBusMount({
    required this.handler,
    required this.httpBusPort,
    required SshMemberSession memberSession,
    required this.storageFs,
    required this.arch,
    this.remoteOs = RemoteOs.posix,
    this.relayProvisioner = const RelayProvisioner(),
    ReverseTunnel Function()? tunnelFactory,
    String? token,
  })  : memberSession = memberSession,
        token = token ?? _randomToken(),
        _tunnelFactory = tunnelFactory ?? memberSession.newReverseTunnel,
        _remoteRun = null;

  /// Test / harness constructor without a live [SshMemberSession].
  RemoteBusMount.testing({
    required this.handler,
    required this.httpBusPort,
    required this.storageFs,
    required this.arch,
    required RemoteCommandRunner remoteRun,
    required ReverseTunnel Function() tunnelFactory,
    this.remoteOs = RemoteOs.posix,
    this.relayProvisioner = const RelayProvisioner(),
    String? token,
  })  : token = token ?? _randomToken(),
        memberSession = null,
        _tunnelFactory = tunnelFactory,
        _remoteRun = remoteRun;

  final TeammateBusMcpHandler handler;
  final int httpBusPort;
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

  BusRawSocketServer? _rawSocket;
  BusHttpTokenGuard? _httpGuard;
  final _members = <String, _MountedMember>{};
  final _preparedRelay = <String, PreparedRelay>{};

  Future<RemoteBusBinding> bindLongBlockingMember(String memberId) async {
    final existing = _members[memberId];
    if (existing != null) return existing.binding;

    final prepared = _preparedRelay[memberId] ??=
        await relayProvisioner.prepare(
          remoteFs: storageFs,
          run: _run,
          arch: arch,
          remoteOs: remoteOs,
        );

    final raw = await _ensureRawSocket();
    final tunnel = _tunnelFactory();
    try {
      final port = await tunnel.open();
      final pump = TunnelPump(tunnel: tunnel, localPort: raw.port);
      await pump.start();

      final plan = relayProvisioner.planFor(
        prepared: prepared,
        tunnelPort: port,
        token: token,
        memberId: memberId,
      );

      final binding = RemoteBusBinding(
        tunnelPort: port,
        token: token,
        relayArgv: plan.argv,
      );
      _members[memberId] = _MountedMember(tunnel, pump, binding);
      return binding;
    } on Object {
      await tunnel.close();
      rethrow;
    }
  }

  Future<RemoteBusBinding> bindHttpMember(String memberId) async {
    final existing = _members[memberId];
    if (existing != null) return existing.binding;

    final guard = await _ensureHttpGuard();
    final tunnel = _tunnelFactory();
    try {
      final port = await tunnel.open();
      final pump = TunnelPump(tunnel: tunnel, localPort: guard.port);
      await pump.start();

      final binding = RemoteBusBinding(tunnelPort: port, token: token);
      _members[memberId] = _MountedMember(tunnel, pump, binding);
      return binding;
    } on Object {
      await tunnel.close();
      rethrow;
    }
  }

  Future<BusHttpTokenGuard> _ensureHttpGuard() async {
    final existing = _httpGuard;
    if (existing != null) return existing;
    final guard = BusHttpTokenGuard(token: token, upstreamPort: httpBusPort);
    await guard.start();
    _httpGuard = guard;
    return guard;
  }

  Future<BusRawSocketServer> _ensureRawSocket() async {
    final existing = _rawSocket;
    if (existing != null) return existing;
    final server = BusRawSocketServer(handler: handler, token: token);
    await server.start();
    _rawSocket = server;
    return server;
  }

  /// Tears down tunnels and local bus sockets. Does not close [memberSession].
  Future<void> close() async {
    for (final m in _members.values) {
      await m.pump.stop();
      await m.tunnel.close();
    }
    _members.clear();
    _preparedRelay.clear();
    await _rawSocket?.close();
    _rawSocket = null;
    await _httpGuard?.close();
    _httpGuard = null;
  }

  static String _randomToken() {
    final rng = Random.secure();
    return List.generate(24, (_) => rng.nextInt(16).toRadixString(16)).join();
  }
}

class _MountedMember {
  _MountedMember(this.tunnel, this.pump, this.binding);
  final ReverseTunnel tunnel;
  final TunnelPump pump;
  final RemoteBusBinding binding;
}

String archFromUname(String unameM) {
  final m = unameM.trim().toLowerCase();
  return switch (m) {
    'x86_64' || 'amd64' => 'linux-x64',
    'aarch64' || 'arm64' => 'linux-arm64',
    _ => m,
  };
}
