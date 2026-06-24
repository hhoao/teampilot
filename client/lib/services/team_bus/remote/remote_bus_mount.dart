import 'dart:async';
import 'dart:math';

import '../../../models/runtime_target.dart';
import '../../io/filesystem.dart';
import '../mcp/teammate_bus_mcp_handler.dart';
import 'bus_http_token_guard.dart';
import 'bus_raw_socket_server.dart';
import 'member_bus_mcp_config.dart';
import 'relay_provisioner.dart';
import 'reverse_tunnel.dart';

/// Per-session mount that connects **remote** (ssh) members back to the local,
/// in-process teammate bus over an SSH reverse tunnel (P3b, the Android-mixed
/// fix). For a long-blocking member it:
///   1. ensures one shared [BusRawSocketServer] over the session's bus handler,
///   2. opens a [ReverseTunnel] → remote loopback port `<P>`,
///   3. pumps tunnel channels into the raw-socket server,
///   4. provisions a relay (socat/nc/bundled) whose argv dials `127.0.0.1:<P>`
///      and sends the per-session token handshake,
/// and returns the [RemoteBusBinding] the member's MCP config points at.
///
/// The tunnel is injected ([tunnelFactory]) so this is exercised end-to-end with
/// a fake tunnel — no real SSH in tests.
class RemoteBusMount {
  RemoteBusMount({
    required this.handler,
    required this.tunnelFactory,
    required this.remoteFs,
    required this.remoteRun,
    required this.arch,
    required this.httpBusPort,
    this.remoteOs = RemoteOs.posix,
    this.relayProvisioner = const RelayProvisioner(),
    String? token,
  }) : token = token ?? _randomToken();

  final TeammateBusMcpHandler handler;
  final ReverseTunnel Function() tunnelFactory;
  final Filesystem remoteFs;
  final RemoteCommandRunner remoteRun;
  final String arch;

  /// P3e: the remote host OS family, deciding relay strategy (socat/nc vs the
  /// bundled static relay) and other os-specific remote behavior.
  final RemoteOs remoteOs;

  /// The local HTTP bus port ([TeammateBusMcpServer.port]) that cursor's
  /// HTTP-over-tunnel members forward to.
  final int httpBusPort;
  final RelayProvisioner relayProvisioner;

  /// Per-session token: the raw-socket handshake (long-blocking) and the cursor
  /// HTTP header both carry it.
  final String token;

  BusRawSocketServer? _rawSocket;
  BusHttpTokenGuard? _httpGuard;
  final _members = <String, _MountedMember>{};

  /// Binds a long-blocking remote member, returning the relay-over-tunnel binding
  /// for its teammate-bus MCP config. Idempotent per member.
  Future<RemoteBusBinding> bindLongBlockingMember(String memberId) async {
    final existing = _members[memberId];
    if (existing != null) return existing.binding;

    final raw = await _ensureRawSocket();
    final tunnel = tunnelFactory();
    final port = await tunnel.open();
    final pump = TunnelPump(tunnel: tunnel, localPort: raw.port);
    await pump.start();

    final plan = await relayProvisioner.provision(
      remoteFs: remoteFs,
      run: remoteRun,
      tunnelPort: port,
      token: token,
      memberId: memberId,
      arch: arch,
      remoteOs: remoteOs,
    );

    final binding = RemoteBusBinding(
      tunnelPort: port,
      token: token,
      relayArgv: plan.argv,
    );
    _members[memberId] = _MountedMember(tunnel, pump, binding);
    return binding;
  }

  /// Binds a cursor (doorbell) remote member: a reverse tunnel whose remote
  /// loopback port `<P>` forwards straight to the local HTTP bus port. cursor
  /// speaks plain HTTP MCP over it (no relay); the per-session token rides in
  /// the `X-Bus-Token` header (validated by the HTTP bus). Idempotent per member.
  Future<RemoteBusBinding> bindHttpMember(String memberId) async {
    final existing = _members[memberId];
    if (existing != null) return existing.binding;

    // cursor's HTTP traffic is admitted by the token guard (validates
    // X-Bus-Token), which then proxies to the real bus HTTP port — so the local
    // bus port is never reachable over the tunnel without the session token.
    final guard = await _ensureHttpGuard();
    final tunnel = tunnelFactory();
    final port = await tunnel.open();
    final pump = TunnelPump(tunnel: tunnel, localPort: guard.port);
    await pump.start();

    final binding = RemoteBusBinding(tunnelPort: port, token: token);
    _members[memberId] = _MountedMember(tunnel, pump, binding);
    return binding;
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

  /// Tears down every pump, tunnel and the shared raw-socket server. Hung on the
  /// session and called from the tab's dispose path.
  Future<void> close() async {
    for (final m in _members.values) {
      await m.pump.stop();
      await m.tunnel.close();
    }
    _members.clear();
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
