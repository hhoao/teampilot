import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/mcp/team_mcp_linker_service.dart';

void main() {
  late Directory root;
  late CliDataLayout layout;
  late TeamMcpLinkerService linker;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('team_mcp_linker_');
    layout = CliDataLayout(teampilotRoot: root.path);
    linker = TeamMcpLinkerService();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('writes enabled assigned servers to team snapshot', () async {
    final server = McpServer(
      id: 'fetch',
      name: 'fetch',
      server: const {'type': 'stdio', 'command': 'npx'},
      createdAt: 1,
      updatedAt: 1,
    );
    final result = await linker.syncForTeam(
      teamId: 'team-a',
      mcpServerIds: const ['fetch', 'missing'],
      catalog: [server],
      layout: layout,
    );
    expect(result.linked, ['fetch']);
    expect(result.skippedMissingIds, ['missing']);

    final file = File(layout.teamMcpServersFile('team-a'));
    expect(await file.exists(), isTrue);
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final servers = json['mcpServers'] as Map<String, Object?>;
    expect(servers.keys, contains('fetch'));
  });

  test('disabled servers are excluded', () async {
    final server = McpServer(
      id: 'off',
      name: 'off',
      server: const {'type': 'stdio', 'command': 'echo'},
      enabled: false,
      createdAt: 1,
      updatedAt: 1,
    );
    await linker.syncForTeam(
      teamId: 'team-a',
      mcpServerIds: const ['off'],
      catalog: [server],
      layout: layout,
    );
    final json = jsonDecode(
      await File(layout.teamMcpServersFile('team-a')).readAsString(),
    ) as Map<String, Object?>;
    expect((json['mcpServers'] as Map).isEmpty, isTrue);
  });
}
