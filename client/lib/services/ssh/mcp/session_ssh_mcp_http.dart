import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:teampilot/services/chat/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/utils/logging/logger.dart';

import 'session_ssh_mcp_constants.dart';
import 'session_ssh_mcp_operations.dart';

const _tpSessionZoneKey = #sessionSshMcpTpSessionId;
const _tpMemberZoneKey = #sessionSshMcpTpMemberId;

const _allowedHosts = {'127.0.0.1', 'localhost'};

/// Streamable HTTP adapter: mcp_dart transports keyed by MCP session id.
///
/// TeamPilot session comes from [teammateBusMcpSessionHeader] (`X-Session`).
/// Missing / unknown sessions still run MCP initialize; tools return
/// `isError` JSON, never HTTP 400.
class SessionSshMcpHttpAdapter {
  SessionSshMcpHttpAdapter({
    required SessionSshMcpOperations operations,
    required Future<SessionSshMcpContext?> Function(
      String sessionId,
      String? memberId,
    )
    resolveContext,
  }) : _operations = operations,
       _resolveContext = resolveContext;

  final SessionSshMcpOperations _operations;
  final Future<SessionSshMcpContext?> Function(
    String sessionId,
    String? memberId,
  )
  _resolveContext;
  final _transports = <String, StreamableHTTPServerTransport>{};

  Future<void> handle(HttpRequest request) async {
    final tpSession = _header(request, teammateBusMcpSessionHeader);
    final tpMember = _header(request, teammateBusMcpMemberHeader);
    await runZoned(
      () => _dispatch(request),
      zoneValues: {
        _tpSessionZoneKey: tpSession,
        _tpMemberZoneKey: tpMember.isEmpty ? null : tpMember,
      },
    );
  }

  Future<void> close() async {
    final transports = List<StreamableHTTPServerTransport>.of(
      _transports.values,
    );
    _transports.clear();
    for (final transport in transports) {
      await transport.close();
    }
  }

  Future<void> _dispatch(HttpRequest request) async {
    switch (request.method) {
      case 'POST':
        await _handlePost(request);
      case 'GET':
      case 'DELETE':
        await _handleSessioned(request);
      default:
        request.response
          ..statusCode = HttpStatus.methodNotAllowed
          ..headers.set(HttpHeaders.allowHeader, 'GET, POST, DELETE');
        await request.response.close();
    }
  }

  Future<void> _handlePost(HttpRequest request) async {
    try {
      final raw = await utf8.decoder.bind(request).join();
      final body = raw.isEmpty ? null : jsonDecode(raw);
      final mcpSessionId = request.headers.value('mcp-session-id');
      StreamableHTTPServerTransport? transport;

      if (mcpSessionId != null && _transports.containsKey(mcpSessionId)) {
        transport = _transports[mcpSessionId];
      } else if (mcpSessionId == null && _canHandleSessionless(request, body)) {
        await _handleNewSession(request, body);
        return;
      } else {
        request.response
          ..statusCode = mcpSessionId == null
              ? HttpStatus.badRequest
              : HttpStatus.notFound
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'jsonrpc': '2.0',
              'error': {
                'code': -32000,
                'message': mcpSessionId == null
                    ? 'Bad Request: sessionless requests must be initialize'
                    : 'Session not found',
              },
              'id': null,
            }),
          );
        await request.response.close();
        return;
      }

      await transport!.handleRequest(request, body);
    } catch (error, stack) {
      AppLogger.instance.e(
        'SSH MCP POST failed',
        error: error,
        stackTrace: stack,
      );
      await _writeInternalError(request);
    }
  }

  Future<void> _handleNewSession(HttpRequest request, dynamic body) async {
    late final StreamableHTTPServerTransport transport;
    transport = StreamableHTTPServerTransport(
      options: StreamableHTTPServerTransportOptions(
        sessionIdGenerator: generateUUID,
        eventStore: InMemoryEventStore(),
        enableJsonResponse: true,
        enableDnsRebindingProtection: true,
        allowedHosts: _allowedHosts,
        onsessioninitialized: (sessionId) {
          _transports[sessionId] = transport;
        },
      ),
    );
    transport.onclose = () {
      final sid = transport.sessionId;
      if (sid != null) _transports.remove(sid);
    };

    final server = _createServer();
    await server.connect(transport);
    await transport.handleRequest(request, body);
  }

  Future<void> _handleSessioned(HttpRequest request) async {
    final mcpSessionId = request.headers.value('mcp-session-id');
    final transport = mcpSessionId == null ? null : _transports[mcpSessionId];
    if (transport == null) {
      request.response.statusCode = mcpSessionId == null
          ? HttpStatus.badRequest
          : HttpStatus.notFound;
      await request.response.close();
      return;
    }
    await transport.handleRequest(request);
  }

  McpServer _createServer() {
    final server = McpServer(
      const Implementation(name: 'teampilot-ssh', version: '1.0.0'),
      options: const McpServerOptions(protocol: McpProtocol.stable),
    );

    server.registerTool(
      sessionSshMcpToolListServers,
      description: 'List SSH servers available to this session.',
      inputSchema: JsonSchema.object(properties: const {}),
      callback: (args, extra) =>
          _runTool((ctx, a) => _operations.listServers(ctx, a), args),
    );
    server.registerTool(
      sessionSshMcpToolExecuteCommand,
      description: 'Run a command on a workspace SSH target.',
      inputSchema: JsonSchema.object(
        properties: {
          'cmdString': JsonSchema.string(description: 'Shell command'),
          'connectionName': JsonSchema.string(
            description: 'Profile id or unique name',
          ),
          'cwd': JsonSchema.string(description: 'Remote working directory'),
          'timeout': JsonSchema.number(description: 'Timeout in milliseconds'),
        },
        required: const ['cmdString'],
      ),
      callback: (args, extra) => _runTool(_operations.executeCommand, args),
    );
    server.registerTool(
      sessionSshMcpToolUpload,
      description: 'Upload a local file to a workspace SSH target.',
      inputSchema: JsonSchema.object(
        properties: {
          'localPath': JsonSchema.string(),
          'remotePath': JsonSchema.string(),
          'connectionName': JsonSchema.string(),
        },
        required: const ['localPath', 'remotePath'],
      ),
      callback: (args, extra) => _runTool(_operations.upload, args),
    );
    server.registerTool(
      sessionSshMcpToolDownload,
      description: 'Download a remote file onto the local workspace.',
      inputSchema: JsonSchema.object(
        properties: {
          'localPath': JsonSchema.string(),
          'remotePath': JsonSchema.string(),
          'connectionName': JsonSchema.string(),
        },
        required: const ['localPath', 'remotePath'],
      ),
      callback: (args, extra) => _runTool(_operations.download, args),
    );
    return server;
  }

  Future<CallToolResult> _runTool(
    Future<SessionSshMcpToolResult> Function(
      SessionSshMcpContext context,
      Map<String, Object?> args,
    )
    invoke,
    Map<String, dynamic> args,
  ) async {
    final sessionId = Zone.current[_tpSessionZoneKey] as String? ?? '';
    if (sessionId.isEmpty) {
      return _errorResult(sessionSshMcpErrorInvalidParams, 'Missing X-Session');
    }
    final memberId = Zone.current[_tpMemberZoneKey] as String?;
    final context = await _resolveContext(sessionId, memberId);
    if (context == null) {
      return _errorResult(sessionSshMcpErrorInvalidParams, 'Unknown session');
    }
    final result = await invoke(context, _asArgs(args));
    final text = result.isError ? '${result.code}:${result.text}' : result.text;
    return CallToolResult(
      isError: result.isError,
      content: [TextContent(text: text)],
    );
  }

  static CallToolResult _errorResult(String code, String message) {
    return CallToolResult(
      isError: true,
      content: [TextContent(text: '$code:$message')],
    );
  }

  static Map<String, Object?> _asArgs(Map<String, dynamic> args) {
    return {for (final e in args.entries) e.key: e.value};
  }

  static bool _canHandleSessionless(HttpRequest request, dynamic body) {
    if (body is Map && body['method'] == Method.initialize) return true;
    final version = request.headers.value('mcp-protocol-version')?.trim();
    return version != null && isStatelessProtocolVersion(version);
  }

  static Future<void> _writeInternalError(HttpRequest request) async {
    try {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'jsonrpc': '2.0',
            'error': {'code': -32603, 'message': 'Internal Server Error'},
            'id': null,
          }),
        );
      await request.response.close();
    } catch (_) {}
  }
}

String _header(HttpRequest request, String name) {
  final want = name.toLowerCase();
  final direct =
      request.headers.value(want)?.trim() ??
      request.headers.value(name)?.trim();
  if (direct != null && direct.isNotEmpty) return direct;
  var found = '';
  request.headers.forEach((key, values) {
    if (found.isNotEmpty) return;
    if (key.toLowerCase() == want && values.isNotEmpty) {
      found = values.first.trim();
    }
  });
  return found;
}
