import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/mcp_probe_snapshot.dart';
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/services/mcp/mcp_probe_handshake.dart';
import 'package:teampilot/services/mcp/mcp_server_probe_service.dart';

import 'support/fake_mcp_probe_handshake.dart';

McpServer server(String id, {bool enabled = true}) => McpServer(
  id: id,
  name: id,
  enabled: enabled,
  server: const {'type': 'stdio', 'command': 'npx'},
);

void main() {
  test('probeEnabled skips disabled servers', () async {
    final fake = FakeMcpProbeHandshake();
    final service = McpServerProbeService(handshake: fake);
    final snaps = <String, McpProbeSnapshot>{};
    await service.probeEnabled(
      [server('a'), server('b', enabled: false)],
      onSnapshot: (id, snap) => snaps[id] = snap,
    );
    expect(fake.calledIds, ['a']);
    expect(snaps['a']!.status, McpProbeStatus.online);
    expect(snaps.containsKey('b'), isFalse);
  });

  test('timeout marks offline and aborts handshake', () async {
    final fake = FakeMcpProbeHandshake(delay: const Duration(milliseconds: 80));
    final service = McpServerProbeService(
      handshake: fake,
      timeout: const Duration(milliseconds: 20),
    );
    final snaps = <String, McpProbeSnapshot>{};
    await service.probeOne(
      server('slow'),
      onSnapshot: (id, snap) => snaps[id] = snap,
    );
    expect(snaps['slow']!.status, McpProbeStatus.offline);
    expect(fake.abortedKeys, isNotEmpty);
  });

  test('stale generation is discarded', () async {
    final fake = FakeMcpProbeHandshake(delay: const Duration(milliseconds: 40));
    final service = McpServerProbeService(
      handshake: fake,
      timeout: const Duration(seconds: 2),
    );
    final snaps = <String, McpProbeSnapshot>{};
    final first = service.probeOne(
      server('x'),
      onSnapshot: (id, snap) => snaps[id] = snap,
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    fake.delay = Duration.zero;
    fake.resultBuilder = (_) =>
        const McpHandshakeResult.ok([McpProbeTool(name: 'newer')]);
    await service.probeOne(
      server('x'),
      onSnapshot: (id, snap) => snaps[id] = snap,
    );
    await first;
    expect(snaps['x']!.tools.single.name, 'newer');
  });

  test('fourth probe waits until a slot frees', () async {
    final fake = FakeMcpProbeHandshake(delay: const Duration(milliseconds: 30));
    final service = McpServerProbeService(
      handshake: fake,
      maxConcurrent: 3,
      timeout: const Duration(seconds: 2),
    );
    final snaps = <String, McpProbeSnapshot>{};
    await Future.wait([
      for (final id in ['a', 'b', 'c', 'd'])
        service.probeOne(server(id), onSnapshot: (i, s) => snaps[i] = s),
    ]);
    expect(fake.maxInFlight, 3);
    expect(snaps.length, 4);
  });

  test('collectListedTools follows nextCursor then stops at maxPages', () async {
    var page = 0;
    final tools = await collectListedTools(
      maxPages: 2,
      listPage: (cursor) async {
        page++;
        return (
          tools: [McpProbeTool(name: 't$page')],
          nextCursor: page == 1 ? 'next' : 'still-more',
        );
      },
    );
    expect(tools.map((t) => t.name).toList(), ['t1', 't2']);
    expect(page, 2);
  });
}
