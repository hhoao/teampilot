import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/mcp_cubit.dart';
import 'package:teampilot/models/mcp_probe_snapshot.dart';
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/repositories/mcp_repository.dart';
import 'package:teampilot/services/mcp/mcp_server_probe_service.dart';

import '../services/mcp/support/fake_mcp_probe_handshake.dart';
import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  McpServer server({String id = 'a', bool enabled = true}) => McpServer(
    id: id,
    name: id,
    enabled: enabled,
    server: const {'type': 'stdio', 'command': 'npx'},
  );

  McpCubit cubitWith(FakeMcpProbeHandshake fake) => McpCubit(
    McpRepository(storage: testHomeStorage),
    storage: testHomeStorage,
    probeService: McpServerProbeService(
      handshake: fake,
      timeout: const Duration(seconds: 2),
    ),
  );

  test('loadAll does not probe', () async {
    final fake = FakeMcpProbeHandshake();
    final cubit = cubitWith(fake);
    addTearDown(cubit.close);
    await cubit.upsert(server());
    await cubit.loadAll();
    expect(fake.calledIds, isEmpty);
  });

  test('probeEnabled covers only enabled servers', () async {
    final fake = FakeMcpProbeHandshake();
    final cubit = cubitWith(fake);
    addTearDown(cubit.close);
    await cubit.upsert(server(id: 'on'));
    await cubit.upsert(server(id: 'off', enabled: false));
    await cubit.probeEnabled();
    expect(fake.calledIds, ['on']);
    expect(cubit.state.probes['on']!.status, McpProbeStatus.online);
    expect(cubit.state.probes.containsKey('off'), isFalse);
  });

  test('disabling clears snapshot', () async {
    final fake = FakeMcpProbeHandshake();
    final cubit = cubitWith(fake);
    addTearDown(cubit.close);
    await cubit.upsert(server());
    await cubit.probeEnabled();
    expect(cubit.state.probes['a'], isNotNull);
    await cubit.toggleEnabled(server(), false);
    expect(cubit.state.probes.containsKey('a'), isFalse);
  });

  test('late result after close is ignored', () async {
    final fake = FakeMcpProbeHandshake(delay: const Duration(milliseconds: 80));
    final cubit = cubitWith(fake);
    await cubit.upsert(server());
    final pending = cubit.probeOne('a');
    await cubit.close();
    final probesAfterClose = Map<String, McpProbeSnapshot>.from(
      cubit.state.probes,
    );
    await pending;
    expect(cubit.isClosed, isTrue);
    expect(cubit.state.probes, probesAfterClose);
  });
}
