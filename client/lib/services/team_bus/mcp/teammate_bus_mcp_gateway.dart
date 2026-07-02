import 'dart:io';

import 'teammate_bus_mcp_config.dart';
import 'teammate_bus_mcp_handler.dart';
import 'teammate_bus_mcp_http_delegate.dart';
import 'teammate_bus_session_registry.dart';
import '../remote/bus_raw_socket_server.dart';

/// App-wide loopback HTTP gateway routing MCP requests to per-session handlers.
class TeammateBusMcpGateway {
  TeammateBusMcpGateway({this.progressInterval = const Duration(seconds: 20)});

  final Duration progressInterval;

  final _registry = TeammateBusSessionRegistry();
  final _delegates = <String, TeammateBusMcpHttpDelegate>{};
  HttpServer? _http;
  BusRawSocketServer? _rawSocket;

  Future<void> ensureStarted() async {
    if (_http != null && _rawSocket != null) return;
    if (_http == null) {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _http = server;
      server.listen(_onRequest);
    }
    if (_rawSocket == null) {
      _rawSocket = BusRawSocketServer.multiplexed(registry: _registry);
      await _rawSocket!.start();
    }
  }

  Uri get mcpEndpoint => Uri.parse('http://127.0.0.1:${_http!.port}/mcp');

  Uri get idleEndpoint => Uri.parse('http://127.0.0.1:${_http!.port}/idle');

  int get rawSocketPort => _rawSocket!.port;

  bool isSessionRegistered(String sessionId) =>
      _registry.handlerForSession(sessionId) != null;

  TeammateBusSessionRegistration register({
    required String sessionId,
    required TeammateBusMcpHandler handler,
  }) {
    final reg = _registry.register(sessionId: sessionId, handler: handler);
    _delegates[sessionId] = TeammateBusMcpHttpDelegate(
      handler: handler,
      progressInterval: progressInterval,
    );
    return reg;
  }

  Future<void> unregister(String sessionId) async {
    _delegates.remove(sessionId)?.cancelAllStreams();
    _registry.unregister(sessionId);
  }

  Future<void> _onRequest(HttpRequest request) async {
    try {
      final sessionId = _resolveSessionId(request);
      if (sessionId == null) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      final delegate = _delegates[sessionId];
      if (delegate == null) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      final member = request.headers.value('x-member')?.trim() ?? '';

      if (request.method == 'POST' && request.uri.path == '/idle') {
        await delegate.handleIdleRequest(request, memberId: member);
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/mcp') {
        await delegate.handleMcpRequest(request, memberId: member);
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  String? _resolveSessionId(HttpRequest request) {
    final sessionHeader =
        request.headers.value(teammateBusMcpSessionHeader.toLowerCase())?.trim();
    if (sessionHeader != null && sessionHeader.isNotEmpty) {
      return sessionHeader;
    }

    final token =
        request.headers.value(teammateBusTokenHeader.toLowerCase())?.trim();
    if (token != null && token.isNotEmpty) {
      return _registry.sessionForToken(token);
    }

    return null;
  }
}
