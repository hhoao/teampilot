import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/mcp_cubit.dart';
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/repositories/mcp_repository.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  McpServer server({bool enabled = true}) => McpServer(
    id: 'vscode-mcp',
    name: 'vscode-mcp',
    enabled: enabled,
    server: const {'type': 'stdio', 'command': 'npx'},
    createdAt: 1,
    updatedAt: 1,
  );

  test('disabling a catalog MCP unbinds workspace and team ids', () async {
    final unbound = <String>[];
    final cubit = McpCubit(
      McpRepository(storage: testHomeStorage),
      storage: testHomeStorage,
      onMcpUnbound: (id) async => unbound.add(id),
    );
    addTearDown(cubit.close);

    await cubit.upsert(server());
    expect(unbound, isEmpty);

    await cubit.toggleEnabled(server(), false);
    expect(unbound, ['vscode-mcp']);
  });

  test('deleting a catalog MCP unbinds workspace and team ids', () async {
    final unbound = <String>[];
    final cubit = McpCubit(
      McpRepository(storage: testHomeStorage),
      storage: testHomeStorage,
      onMcpUnbound: (id) async => unbound.add(id),
    );
    addTearDown(cubit.close);

    await cubit.upsert(server());
    await cubit.delete('vscode-mcp');
    expect(unbound, ['vscode-mcp']);
  });
}
