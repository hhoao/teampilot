import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/mcp_probe_snapshot.dart';

void main() {
  test('online snapshot exposes tool count', () {
    const snap = McpProbeSnapshot(
      status: McpProbeStatus.online,
      tools: [
        McpProbeTool(name: 'health_check', description: 'Ping'),
        McpProbeTool(name: 'open_files'),
      ],
      generation: 2,
    );
    expect(snap.tools.length, 2);
    expect(snap.tools.first.description, 'Ping');
    expect(snap, isNot(const McpProbeSnapshot(status: McpProbeStatus.checking)));
  });

  test('handshake fail carries needsAuth without tools', () {
    const result = McpHandshakeResult.fail(status: McpProbeStatus.needsAuth);
    expect(result.status, McpProbeStatus.needsAuth);
    expect(result.tools, isEmpty);
  });
}
