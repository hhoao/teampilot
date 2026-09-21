import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:teampilot/services/mcp/mcp_dart_probe_handshake.dart';

void main() {
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
}
