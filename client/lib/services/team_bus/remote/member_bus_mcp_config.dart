import '../mcp/teammate_bus_mcp_config.dart';

/// Per-remote-member binding produced by the reverse-tunnel mount: the remote
/// loopback port `<P>` the member's CLI dials, the per-session token guarding the
/// tunnel, and — for long-blocking CLIs — the relay argv that injects the
/// handshake frame and pipes the CLI's MCP stdio to that port.
class RemoteBusBinding {
  const RemoteBusBinding({
    required this.tunnelPort,
    required this.token,
    this.relayArgv,
  });

  /// Remote loopback port forwarded back to the local bus by the reverse tunnel.
  final int tunnelPort;

  /// Per-session token. For long-blocking CLIs it rides in the relay handshake
  /// frame; for cursor (HTTP) it rides in [teammateBusTokenHeader].
  final String token;

  /// Relay command argv for long-blocking CLIs (relay-over-tunnel). Null for
  /// cursor (plain HTTP-over-tunnel needs no relay).
  final List<String>? relayArgv;
}

/// Builds the teammate-bus MCP server config dict for one member, selecting the
/// transport by whether the member runs remotely and whether its CLI parks in a
/// long-blocking `wait_for_message`.
///
/// - **local** member → unchanged: claude on the native backend with a resolvable
///   bridge → stdio bridge to the bare loopback [localEndpoint]; otherwise HTTP
///   to [localEndpoint].
/// - **remote + long-blocking** (claude/flashskyai/codex/opencode) → stdio relay
///   over the reverse tunnel: `command`/`args` come from [RemoteBusBinding.relayArgv]
///   which dials `127.0.0.1:<P>` and sends the token handshake.
/// - **remote + cursor** (doorbell) → HTTP over the reverse tunnel: `url` points
///   at `127.0.0.1:<P>`, guarded by the session token header.
///
/// The remote branches point the member's CLI at the **tunnel port** `<P>` rather
/// than the bare in-process bus loopback the remote host cannot reach — this is
/// the Android-mixed fix.
Map<String, Object?> buildMemberBusMcpConfig({
  required String memberId,
  required Uri localEndpoint,
  required bool longBlocking,
  String? localStdioBridgePath,
  RemoteBusBinding? remote,
}) {
  if (remote != null) {
    if (longBlocking) {
      final argv = remote.relayArgv;
      if (argv == null || argv.isEmpty) {
        throw ArgumentError(
          'long-blocking remote member "$memberId" needs a relay argv',
        );
      }
      return {
        'command': argv.first,
        'args': argv.sublist(1),
      };
    }
    // cursor: plain HTTP over the tunnel, token in a header.
    return {
      'type': 'http',
      'url': 'http://127.0.0.1:${remote.tunnelPort}/mcp',
      'headers': {
        teammateBusMcpMemberHeader: memberId,
        teammateBusTokenHeader: remote.token,
      },
    };
  }

  if (localStdioBridgePath != null) {
    return teammateBusMcpServerConfigStdio(
      bridgePath: localStdioBridgePath,
      endpoint: localEndpoint,
      memberId: memberId,
    );
  }
  return teammateBusMcpServerConfig(endpoint: localEndpoint, memberId: memberId);
}
