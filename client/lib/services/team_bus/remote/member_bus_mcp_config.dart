import '../mcp/teammate_bus_mcp_config.dart';

/// Per-remote-member binding produced by the reverse-tunnel mount.
///
/// MCP and idle HTTP use **separate** remote loopback ports for long-blocking
/// CLIs: raw-socket relay for `wait_for_message`, HTTP guard tunnel for `/idle`.
/// Cursor (doorbell) shares one HTTP tunnel for MCP + idle.
class RemoteBusBinding {
  const RemoteBusBinding({
    required this.token,
    required this.idleHttpTunnelPort,
    this.mcpRawTunnelPort,
    this.mcpRelayArgv,
    this.mcpHttpTunnelPort,
  });

  final String token;

  /// Remote loopback port for Stop-hook / idle-plugin HTTP (`/idle`).
  final int idleHttpTunnelPort;

  /// Raw-socket MCP tunnel port (long-blocking CLIs only).
  final int? mcpRawTunnelPort;

  /// Relay argv dialing [mcpRawTunnelPort] (long-blocking CLIs only).
  final List<String>? mcpRelayArgv;

  /// HTTP MCP tunnel port (cursor only; same tunnel as [idleHttpTunnelPort]).
  final int? mcpHttpTunnelPort;

  String get idleUrl => 'http://127.0.0.1:$idleHttpTunnelPort/idle';

  bool get isLongBlocking => mcpRelayArgv != null;
}

/// Builds the teammate-bus MCP server config dict for one member, selecting the
/// transport by whether the member runs remotely and whether its CLI parks in a
/// long-blocking `wait_for_message`.
///
/// - **local** member → claude + native PTY bridge → stdio; else HTTP loopback.
/// - **remote + long-blocking** → stdio relay over [mcpRawTunnelPort].
/// - **remote + cursor** → HTTP over [mcpHttpTunnelPort] + session token header.
Map<String, Object?> buildMemberBusMcpConfig({
  required String memberId,
  required Uri localEndpoint,
  required bool longBlocking,
  String? localStdioBridgePath,
  RemoteBusBinding? remote,
}) {
  if (remote != null) {
    if (longBlocking) {
      final argv = remote.mcpRelayArgv;
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
    final httpPort = remote.mcpHttpTunnelPort;
    if (httpPort == null) {
      throw ArgumentError(
        'non-blocking remote member "$memberId" needs an HTTP MCP tunnel port',
      );
    }
    return {
      'type': 'http',
      'url': 'http://127.0.0.1:$httpPort/mcp',
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
