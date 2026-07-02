import 'remote/member_bus_mcp_config.dart';
import 'mcp/teammate_bus_mcp_config.dart';
import 'mcp/teammate_bus_mcp_gateway.dart';

/// Where a mixed-mode member reports turn-end idle (Stop hook / idle plugin).
///
/// Local members dial the in-process bus loopback directly. Remote (ssh) members
/// dial their reverse-tunnel loopback port and must include [token] for
/// [BusHttpTokenGuard].
class MemberBusIdleEndpoint {
  const MemberBusIdleEndpoint({
    required this.url,
    this.token,
    this.sessionId,
  });

  final String url;

  /// Per-session bus token; set for remote members only.
  final String? token;

  /// Local gateway routing header value (mixed sessions on loopback).
  final String? sessionId;

  bool get isRemote => token != null && token!.isNotEmpty;

  int? get port {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasPort) return null;
    return uri.port;
  }

  factory MemberBusIdleEndpoint.local(
    TeammateBusMcpGateway gateway, {
    required String sessionId,
  }) =>
      MemberBusIdleEndpoint(
        url: gateway.idleEndpoint.toString(),
        sessionId: sessionId,
      );

  factory MemberBusIdleEndpoint.remote(RemoteBusBinding binding) =>
      MemberBusIdleEndpoint(url: binding.idleUrl, token: binding.token);

  Map<String, String> headersFor(String memberId) {
    final headers = <String, String>{teammateBusMcpMemberHeader: memberId};
    final session = sessionId;
    if (session != null && session.isNotEmpty) {
      headers[teammateBusMcpSessionHeader] = session;
    }
    final t = token;
    if (t != null && t.isNotEmpty) {
      headers[teammateBusTokenHeader] = t;
    }
    return headers;
  }
}
