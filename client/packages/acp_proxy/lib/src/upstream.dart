import 'launch_meta.dart';

/// ACP client the proxy keeps alive for one CLI session.
///
/// Production opens a process. Tests supply a fake.
abstract class AcpUpstream {
  bool get alive;

  Future<String> openNew({
    required AcpProxyLaunchMeta meta,
    required String cwd,
    required List<Map<String, Object?>> mcpServers,
  });

  Future<void> openLoad({required String sessionId, required String cwd});

  Future<void> prompt(String text);

  Future<void> cancel();

  Future<void> close();

  Stream<Map<String, Object?>> get updates;

  /// CLI → client requests (`session/request_permission`, `cursor/ask_question`,
  /// `cursor/create_plan`). The proxy completes each one.
  Stream<AcpClientRequest> get clientRequests;

  void completeClientRequest(Object id, Map<String, Object?> result);
}

/// One CLI request that needs a client result.
class AcpClientRequest {
  const AcpClientRequest({
    required this.id,
    required this.method,
    required this.params,
  });

  final Object id;
  final String method;
  final Map<String, Object?> params;
}
