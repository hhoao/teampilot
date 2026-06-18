import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/mcp/profile_mcp_linker_service.dart';

void main() {
  late Directory root;
  late RuntimeLayout layout;
  late ProfileMcpLinkerService linker;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('team_mcp_linker_');
    layout = RuntimeLayout(teampilotRoot: root.path);
    linker = ProfileMcpLinkerService();
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
    final result = await linker.syncForProfile(
      profileId: 'team-a',
      mcpServerIds: const ['fetch', 'missing'],
      catalog: [server],
      layout: layout,
    );
    expect(result.linked, ['fetch']);
    expect(result.skippedMissingIds, ['missing']);

    final file = File(layout.identityMcpServersFile('team-a'));
    expect(await file.exists(), isTrue);
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final servers = json['mcpServers'] as Map<String, Object?>;
    expect(servers.keys, contains('fetch'));
    expect(json.containsKey('smitheryServerKeys'), isFalse);
  });

  test('records smitheryServerKeys for smithery catalog entries', () async {
    final server = McpServer(
      id: 'github',
      name: 'GitHub',
      server: const {
        'type': 'http',
        'url': 'https://github.run.tools',
      },
      smitheryHosted: true,
      createdAt: 1,
      updatedAt: 1,
    );
    await linker.syncForProfile(
      profileId: 'team-a',
      mcpServerIds: const ['github'],
      catalog: [server],
      layout: layout,
    );
    final json = jsonDecode(
      await File(layout.identityMcpServersFile('team-a')).readAsString(),
    ) as Map<String, Object?>;
    expect(json['smitheryServerKeys'], ['GitHub']);
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
    await linker.syncForProfile(
      profileId: 'team-a',
      mcpServerIds: const ['off'],
      catalog: [server],
      layout: layout,
    );
    final json = jsonDecode(
      await File(layout.identityMcpServersFile('team-a')).readAsString(),
    ) as Map<String, Object?>;
    expect((json['mcpServers'] as Map).isEmpty, isTrue);
  });
}
