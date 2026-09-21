import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart' hide McpServer;
import 'package:teampilot/models/mcp_probe_snapshot.dart';
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/services/mcp/mcp_credentials_store.dart';
import 'package:teampilot/services/mcp/mcp_dart_probe_handshake.dart';

import '../../support/post_frame_test_harness.dart';

class _ThrowingCredentialsStore extends McpCredentialsStore {
  _ThrowingCredentialsStore({required super.fs});

  @override
  Future<Map<String, Object?>> read(String configDir) async {
    throw const FormatException('Unexpected token in {"accessToken":"sekrit"}');
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('streamable HTTP POST 401 McpError is needsAuth', () {
    final error = McpError(
      0,
      'Error POSTing to endpoint (HTTP 401): {"error":"unauthorized"}',
    );
    expect(mcpProbeErrorNeedsAuth(error), isTrue);
  });

  test('streamable HTTP POST 403 McpError is needsAuth', () {
    final error = McpError(
      0,
      'Error POSTing to endpoint (HTTP 403): forbidden body',
    );
    expect(mcpProbeErrorNeedsAuth(error), isTrue);
  });

  test('streamable HTTP POST 400 McpError is not needsAuth', () {
    final error = McpError(
      0,
      'Error POSTing to endpoint (HTTP 400): bad request',
    );
    expect(mcpProbeErrorNeedsAuth(error), isFalse);
  });

  test('missing tools capability is treated as empty online list', () {
    expect(mcpProbeShouldListTools(null), isFalse);
    expect(mcpProbeShouldListTools(const ServerCapabilities()), isFalse);
    expect(
      mcpProbeShouldListTools(
        const ServerCapabilities(tools: ServerCapabilitiesTools()),
      ),
      isTrue,
    );
  });

  test('corrupt credentials become offline instead of throwing', () async {
    final handshake = McpDartProbeHandshake(
      storage: testHomeStorage,
      credentials: _ThrowingCredentialsStore(fs: testHomeStorage.fs),
    );
    final result = await handshake.listTools(
      const McpServer(
        id: 'stdio-a',
        name: 'stdio-a',
        server: {'type': 'stdio', 'command': 'npx'},
      ),
      probeKey: 'stdio-a#1',
    );
    expect(result.status, McpProbeStatus.offline);
  });
}
