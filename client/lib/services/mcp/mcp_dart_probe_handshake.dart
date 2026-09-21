import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart' hide McpServer;

import '../../models/mcp_probe_snapshot.dart';
import '../../models/mcp_registry_source.dart';
import '../../models/mcp_server.dart';
import '../../models/mcp_server_spec.dart';
import '../../utils/logging/logger.dart';
import '../storage/home_storage.dart';
import 'mcp_credentials_store.dart';
import 'mcp_oauth_flow.dart';
import 'mcp_oauth_server_key.dart';
import 'mcp_probe_handshake.dart';
import 'mcp_probe_headers.dart';
import 'mcp_registry_config_service.dart';
import 'smithery_mcp_auth.dart';

const _clientInfo = Implementation(name: 'teampilot', version: '1.0.0');

/// True when a handshake error means the remote requires auth.
///
/// mcp_dart 2.4.2 [StreamableHttpClientTransport.send] with no authProvider
/// throws [McpError] code 0 (`Error POSTing to endpoint (HTTP 401|403): …`),
/// not [UnauthorizedError] / [StreamableHttpError]. Match that prefix only;
/// do not log [McpError.message] (it may include the response body).
bool mcpProbeErrorNeedsAuth(Object error) {
  if (error is UnauthorizedError) return true;
  if (error is StreamableHttpError) {
    return error.code == 401 || error.code == 403;
  }
  // Catalog still has `type: sse`.
  // ignore: deprecated_member_use
  if (error is SseClientError) {
    return error.code == 401 || error.code == 403;
  }
  if (error is McpError && error.code == 0) {
    final message = error.message;
    return message.startsWith('Error POSTing to endpoint (HTTP 401)') ||
        message.startsWith('Error POSTing to endpoint (HTTP 403)');
  }
  return false;
}

/// Production [McpProbeHandshake] using mcp_dart [McpClient].
class McpDartProbeHandshake implements McpProbeHandshake {
  McpDartProbeHandshake({
    required HomeStorage storage,
    McpCredentialsStore? credentials,
    McpRegistryConfigService? registryConfig,
    String? Function(String name)? readEnv,
  }) : _storage = storage,
       _credentials = credentials ?? McpCredentialsStore(fs: storage.fs),
       _registryConfig =
           registryConfig ??
           McpRegistryConfigService(
             teampilotRoot: storage.appDataRoot,
             fs: storage.fs,
           ),
       _readEnv = readEnv ?? ((name) => Platform.environment[name]);

  final HomeStorage _storage;
  final McpCredentialsStore _credentials;
  final McpRegistryConfigService _registryConfig;
  final String? Function(String name) _readEnv;
  final Map<String, McpClient> _live = {};

  @override
  Future<McpHandshakeResult> listTools(
    McpServer server, {
    required String probeKey,
  }) async {
    final spec = Map<String, Object?>.from(server.server);
    final parsed = McpServerSpec.fromCatalogJson(server.configKey, spec);
    if (parsed == null) {
      return const McpHandshakeResult.fail(status: McpProbeStatus.offline);
    }

    final headerInput = await _headerInput(server.configKey, spec);
    if (mcpProbeAuthDecision(headerInput) == McpProbeAuthDecision.needsAuth) {
      return const McpHandshakeResult.fail(status: McpProbeStatus.needsAuth);
    }

    final client = McpClient(_clientInfo);
    _live[probeKey] = client;
    try {
      await client.connect(_transportFor(parsed, spec, headerInput));
      final tools = await collectListedTools(
        listPage: (cursor) => _listPage(client, cursor),
      );
      return McpHandshakeResult.ok(tools);
    } catch (e) {
      return _resultForError(server.id, e);
    } finally {
      await _release(probeKey, client);
    }
  }

  @override
  Future<void> abort(String probeKey) async {
    final client = _live.remove(probeKey);
    if (client == null) return;
    await _closeQuietly(client);
  }

  @override
  Future<void> closeAll() async {
    final clients = _live.values.toList();
    _live.clear();
    for (final client in clients) {
      await _closeQuietly(client);
    }
  }

  Future<McpProbeHeaderInput> _headerInput(
    String serverName,
    Map<String, Object?> spec,
  ) async {
    final data = await _credentials.read(
      McpOAuthFlow.claudeAppConfigDir(_storage),
    );
    final entry = _credentials.oauthEntry(
      data,
      mcpOAuthServerKey(serverName, spec),
    );
    String? oauthAccessToken;
    if (_credentials.hasAccessToken(data, serverName, spec)) {
      oauthAccessToken = entry?['accessToken']?.toString();
    }
    final smitheryApiToken = (await _registryConfig.load())
        .byKind(McpRegistrySourceKind.smithery)
        ?.apiToken;
    return McpProbeHeaderInput(
      spec: spec,
      oauthApplicable:
          mcpServerNeedsOAuthConnect(spec) &&
          !SmitheryMcpAuth.shouldApplyCatalogBearer(spec),
      oauthAccessToken: oauthAccessToken,
      smitheryApiToken: smitheryApiToken,
      readEnv: _readEnv,
    );
  }

  Transport _transportFor(
    McpServerSpec parsed,
    Map<String, Object?> spec,
    McpProbeHeaderInput headerInput,
  ) {
    switch (parsed) {
      case StdioMcpServer s:
        final cwd = s.cwd?.trim() ?? '';
        return StdioClientTransport(
          StdioServerParameters(
            command: s.command,
            args: s.args,
            environment: s.env.isEmpty ? null : s.env,
            workingDirectory: cwd.isEmpty ? null : cwd,
            stderrMode: ProcessStartMode.normal,
            restartOnUnexpectedExit: false,
          ),
        );
      case RemoteMcpServer r:
        final uri = Uri.parse(r.url);
        final headers = buildMcpProbeHeaders(headerInput);
        final type = spec['type']?.toString().trim().toLowerCase() ?? '';
        if (type == 'sse') {
          return _sseTransport(uri, headers);
        }
        return StreamableHttpClientTransport(
          uri,
          opts: StreamableHttpClientTransportOptions(
            requestInit: {'headers': headers},
          ),
        );
    }
  }

  Transport _sseTransport(Uri uri, Map<String, String> headers) {
    // Catalog still has `type: sse`.
    // ignore: deprecated_member_use
    return SseClientTransport(
      uri,
      // ignore: deprecated_member_use
      opts: SseClientTransportOptions(headers: headers),
    );
  }

  Future<({List<McpProbeTool> tools, String? nextCursor})> _listPage(
    McpClient client,
    String? cursor,
  ) async {
    final page = await client.listTools(
      params: ListToolsRequest(cursor: cursor),
    );
    return (
      tools: [
        for (final tool in page.tools)
          McpProbeTool(name: tool.name, description: tool.description ?? ''),
      ],
      nextCursor: page.nextCursor,
    );
  }

  McpHandshakeResult _resultForError(String serverId, Object error) {
    if (mcpProbeErrorNeedsAuth(error)) {
      return const McpHandshakeResult.fail(status: McpProbeStatus.needsAuth);
    }
    appLogger.w(
      '[mcp-probe-handshake] $serverId failed (${error.runtimeType})',
    );
    return const McpHandshakeResult.fail(status: McpProbeStatus.offline);
  }

  Future<void> _release(String probeKey, McpClient client) async {
    if (identical(_live[probeKey], client)) {
      _live.remove(probeKey);
    }
    await _closeQuietly(client);
  }

  Future<void> _closeQuietly(McpClient client) async {
    try {
      await client.close();
    } catch (_) {}
  }
}
