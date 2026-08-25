import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:meta/meta.dart';

import '../../agent_runtime/agent_event_gateway.dart';
import '../../agent_status/ask_user_answer_pending_store.dart';
import '../../catalog/catalog_mcp_constants.dart';
import '../../catalog/catalog_mcp_handler.dart';
import 'jsonrpc.dart';
import 'mcp_method.dart';
import 'toolkit/mcp_tool_response.dart';
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
  final _agentStatusSessions = <String>{};
  final _agentStatusTokenToSession = <String, String>{};
  final _agentStatusSessionToToken = <String, String>{};
  AgentEventGateway? _agentEventGateway;
  AskUserAnswerPendingStore? _askUserAnswerStore;
  CatalogMcpHandler? _catalogHandler;
  Future<CatalogMcpSession?> Function(String sessionId)? _resolveCatalogSession;
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

  /// Closes HTTP + raw-socket listeners (tests / shutdown).
  Future<void> dispose() async {
    for (final sessionId in _delegates.keys.toList()) {
      await unregister(sessionId);
    }
    for (final sessionId in _agentStatusSessions.toList()) {
      unregisterAgentStatusSession(sessionId);
    }
    await _http?.close(force: true);
    _http = null;
    await _rawSocket?.close();
    _rawSocket = null;
  }

  Uri get mcpEndpoint => Uri.parse('http://127.0.0.1:${_http!.port}/mcp');

  Uri get catalogMcpEndpoint =>
      Uri.parse('http://127.0.0.1:${_http!.port}$catalogMcpPath');

  Uri get idleEndpoint => Uri.parse('http://127.0.0.1:${_http!.port}/idle');

  Uri get agentStatusEndpoint =>
      Uri.parse('http://127.0.0.1:${_http!.port}/agent-status');

  Uri get askUserAnswerEndpoint =>
      Uri.parse('http://127.0.0.1:${_http!.port}/ask-user-answer');

  int get httpPort => _http!.port;

  int get rawSocketPort => _rawSocket!.port;

  bool isSessionRegistered(String sessionId) =>
      _registry.handlerForSession(sessionId) != null;

  /// Open SSE `wait_for_message` streams for one session (integration tests).
  @visibleForTesting
  int activeWaitStreamCountFor(String sessionId) =>
      _delegates[sessionId]?.activeWaitStreamCount ?? 0;

  void attachAgentEventGateway(AgentEventGateway gateway) {
    _agentEventGateway = gateway;
  }

  void attachAskUserAnswerStore(AskUserAnswerPendingStore store) {
    _askUserAnswerStore = store;
  }

  void attachCatalogHandler(
    CatalogMcpHandler handler, {
    required Future<CatalogMcpSession?> Function(String sessionId)
    resolveSession,
  }) {
    _catalogHandler = handler;
    _resolveCatalogSession = resolveSession;
  }

  /// Status-only session auth (no TeamBus MCP `_delegates` entry required).
  ///
  /// Returns the remote [X-Bus-Token] value (provided, existing, or generated).
  /// When [token] is omitted and the session is already registered, reuses the
  /// prior token so multi-seat status-only SSH mounts stay authenticated.
  String registerAgentStatusSession({
    required String sessionId,
    String? token,
  }) {
    _agentStatusSessions.add(sessionId);
    final explicit = token != null && token.isNotEmpty ? token : null;
    if (explicit == null) {
      final existing = _agentStatusSessionToToken[sessionId];
      if (existing != null) return existing;
    }
    final previous = _agentStatusSessionToToken.remove(sessionId);
    if (previous != null) {
      _agentStatusTokenToSession.remove(previous);
    }
    final effective = explicit ?? _randomStatusToken();
    _agentStatusTokenToSession[effective] = sessionId;
    _agentStatusSessionToToken[sessionId] = effective;
    return effective;
  }

  void unregisterAgentStatusSession(String sessionId) {
    _agentStatusSessions.remove(sessionId);
    final token = _agentStatusSessionToToken.remove(sessionId);
    if (token != null) {
      _agentStatusTokenToSession.remove(token);
    }
  }

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
      // Ask-user-answer poll is best-effort for OpenCode plugins: prefer 204
      // over 4xx so a missing session/member never breaks the poll loop.
      if (request.method == 'GET' && request.uri.path == '/ask-user-answer') {
        final sessionId = _resolveSessionId(request);
        await _handleAskUserAnswer(request, sessionId: sessionId);
        return;
      }

      // Agent-status is best-effort seat reporting. Never return 4xx here —
      // Claude / flashskyai Stop hooks re-prompt the model on HTTP errors and
      // burn scripted mock turns (or user-visible loops).
      if (request.method == 'POST' && request.uri.path == '/agent-status') {
        final sessionId = _resolveSessionId(request);
        await _handleAgentStatus(request, sessionId: sessionId);
        return;
      }

      // Catalog MCP is available for every session, including Simple
      // (no TeamBus register). Route before the `_delegates` bail-out so
      // missing X-Session is a JSON-RPC/tool error in HTTP 200, not 400.
      if (request.method == 'POST' && request.uri.path == catalogMcpPath) {
        await _handleCatalogMcp(request);
        return;
      }

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

      final member = _headerValue(request.headers, teammateBusMcpMemberHeader);

      if (request.method == 'POST' && request.uri.path == '/idle') {
        // Clear attention before closing the response so clients that drain
        // the body cannot race ahead of the sticky-waiting update (Windows CI).
        await _publishIdle(sessionId: sessionId, memberId: member);
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

  Future<void> _handleAskUserAnswer(
    HttpRequest request, {
    required String? sessionId,
  }) async {
    final store = _askUserAnswerStore;
    final member = _headerValue(request.headers, teammateBusMcpMemberHeader);
    final requestId = request.uri.queryParameters['request_id']?.trim() ?? '';
    final allowed =
        sessionId != null &&
        sessionId.isNotEmpty &&
        (_agentStatusSessions.contains(sessionId) ||
            _delegates.containsKey(sessionId));
    if (store == null || !allowed || member.isEmpty || requestId.isEmpty) {
      await _writeNoContent(request);
      return;
    }

    final entry = store.take(
      sessionId: sessionId,
      memberId: member,
      requestId: requestId,
    );
    if (entry == null) {
      await _writeNoContent(request);
      return;
    }

    final body = <String, Object?>{
      'request_id': entry.requestId,
      'reject': entry.reject,
      if (entry.permissionReply != null)
        'permission_reply': entry.permissionReply,
      if (!entry.reject && entry.permissionReply == null)
        'answers': entry.answers ?? const <List<String>>[],
    };
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      )
      ..write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> _writeNoContent(HttpRequest request) async {
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
  }

  Future<void> _handleAgentStatus(
    HttpRequest request, {
    required String? sessionId,
  }) async {
    final gateway = _agentEventGateway;
    final member = _headerValue(request.headers, teammateBusMcpMemberHeader);
    final allowed =
        sessionId != null &&
        sessionId.isNotEmpty &&
        (_agentStatusSessions.contains(sessionId) ||
            _delegates.containsKey(sessionId));
    if (gateway == null || !allowed || member.isEmpty) {
      await _writeAgentStatusOkEmpty(request);
      return;
    }

    await gateway.handle(request, sessionId: sessionId, memberId: member);
  }

  Future<void> _writeAgentStatusOkEmpty(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      )
      ..write('{}');
    await request.response.close();
  }

  Future<void> _handleCatalogMcp(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final rpc = JsonRpcRequest.tryParse(body);
    final handler = _catalogHandler;
    final resolve = _resolveCatalogSession;
    if (handler == null || resolve == null) {
      await _writeJsonRpc(
        request,
        JsonRpcResponse.error(
          rpc?.id,
          JsonRpcErrorCode.serverError,
          'Catalog MCP is not attached',
        ),
      );
      return;
    }
    if (rpc == null) {
      await _writeJsonRpc(
        request,
        JsonRpcResponse.error(
          null,
          JsonRpcErrorCode.invalidParams,
          'Invalid JSON-RPC request',
        ),
      );
      return;
    }

    final sessionId = _resolveSessionId(request);
    if (sessionId == null || sessionId.isEmpty) {
      await _writeJsonRpc(
        request,
        JsonRpcResponse.error(
          rpc.id,
          JsonRpcErrorCode.invalidParams,
          'Missing X-Session',
        ),
      );
      return;
    }

    final session = await resolve(sessionId);
    if (session == null) {
      await _writeJsonRpc(
        request,
        JsonRpcResponse.error(
          rpc.id,
          JsonRpcErrorCode.invalidParams,
          'Unknown session',
        ),
      );
      return;
    }

    JsonRpcResponse? res;
    try {
      res = await handler.handle(rpc, session);
    } catch (e) {
      res = McpToolResponse.toolError(rpc.id, 'code=install_failed $e');
    }
    if (rpc.isNotification || res == null) {
      request.response.statusCode = HttpStatus.accepted;
      await request.response.close();
      return;
    }
    await _writeJsonRpc(request, res);
  }

  Future<void> _writeJsonRpc(
    HttpRequest request,
    JsonRpcResponse response,
  ) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      )
      ..write(response.encode());
    await request.response.close();
  }

  String? _resolveSessionId(HttpRequest request) {
    final sessionHeader = _headerValue(
      request.headers,
      teammateBusMcpSessionHeader,
    );
    if (sessionHeader.isNotEmpty) {
      return sessionHeader;
    }

    final token = _headerValue(request.headers, teammateBusTokenHeader);
    if (token.isNotEmpty) {
      final fromRegistry = _registry.sessionForToken(token);
      if (fromRegistry != null) return fromRegistry;
      return _agentStatusTokenToSession[token];
    }

    return null;
  }

  Future<void> _publishIdle({
    required String sessionId,
    required String memberId,
  }) async {
    final gateway = _agentEventGateway;
    if (gateway == null) return;
    await gateway.publishIdle(
      sessionId: sessionId,
      memberId: memberId.isEmpty ? null : memberId,
    );
  }
}

/// Case-insensitive header read with forEach fallback (Windows keep-alive).
String _headerValue(HttpHeaders headers, String name) {
  final want = name.toLowerCase();
  final direct = headers.value(want)?.trim() ?? headers.value(name)?.trim();
  if (direct != null && direct.isNotEmpty) return direct;
  var found = '';
  headers.forEach((key, values) {
    if (found.isNotEmpty) return;
    if (key.toLowerCase() == want && values.isNotEmpty) {
      found = values.first.trim();
    }
  });
  return found;
}

String _randomStatusToken() {
  final rng = Random.secure();
  return List.generate(24, (_) => rng.nextInt(16).toRadixString(16)).join();
}
