import 'remote/member_bus_mcp_config.dart';
import 'mcp/teammate_bus_mcp_config.dart';
import 'mcp/teammate_bus_mcp_server.dart';

/// Where a mixed-mode member reports turn-end idle (Stop hook / idle plugin).
///
/// Local members dial the in-process bus loopback directly. Remote (ssh) members
/// dial their reverse-tunnel loopback port and must include [token] for
/// [BusHttpTokenGuard].
class MemberBusIdleEndpoint {
  const MemberBusIdleEndpoint({required this.url, this.token});

  final String url;

  /// Per-session bus token; set for remote members only.
  final String? token;

  bool get isRemote => token != null && token!.isNotEmpty;

  int? get port {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasPort) return null;
    return uri.port;
  }

  factory MemberBusIdleEndpoint.local(TeammateBusMcpServer server) =>
      MemberBusIdleEndpoint(url: server.idleEndpoint.toString());

  factory MemberBusIdleEndpoint.remote(RemoteBusBinding binding) =>
      MemberBusIdleEndpoint(url: binding.idleUrl, token: binding.token);

  Map<String, String> headersFor(String memberId) {
    final headers = <String, String>{teammateBusMcpMemberHeader: memberId};
    final t = token;
    if (t != null && t.isNotEmpty) {
      headers[teammateBusTokenHeader] = t;
    }
    return headers;
  }
}
