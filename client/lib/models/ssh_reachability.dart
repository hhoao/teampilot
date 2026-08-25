enum SshEndpointKind { lan, extra, relay }

enum ConnectPolicy { automatic, lanOnly }

class SshReachabilityEndpoint {
  const SshReachabilityEndpoint({
    required this.kind,
    required this.host,
    required this.port,
  });

  final SshEndpointKind kind;
  final String host;
  final int port;

  static SshReachabilityEndpoint? tryParse(Map<String, Object?> json) {
    final kind = SshEndpointKind.values.where((value) {
      return value.name == json['kind'];
    }).firstOrNull;
    final host = json['host'] as String? ?? '';
    final port = (json['port'] as num?)?.toInt() ?? 22;
    if (kind == null || host.trim().isEmpty || port < 1 || port > 65535) {
      return null;
    }
    return SshReachabilityEndpoint(kind: kind, host: host, port: port);
  }

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'host': host,
    'port': port,
  };
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
