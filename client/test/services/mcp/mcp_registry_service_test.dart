import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/mcp/mcp_registry_service.dart';
import 'package:teampilot/services/mcp/team_mcp_linker_service.dart';
import 'package:teampilot/models/mcp_server.dart';

void main() {
  late Directory root;
  late CliDataLayout layout;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mcp_registry_');
    layout = CliDataLayout(teampilotRoot: root.path);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('merges catalog into claude metadata preserving other servers', () async {
    const teamId = 'team-a';
    const sessionId = 'sess-1';
    final memberDir = layout.memberToolDir(teamId, sessionId, 'claude');
    await Directory(memberDir).create(recursive: true);

    final metaFile = File('$memberDir/.claude.json');
    await metaFile.writeAsString(
      jsonEncode({
        'hasCompletedOnboarding': true,
        'mcpServers': {
          'plugin-srv': {'type': 'stdio', 'command': 'plugin'},
        },
        'projects': {
          '/repo': {'hasTrustDialogAccepted': true},
        },
      }),
    );

    await TeamMcpLinkerService().syncForTeam(
      teamId: teamId,
      mcpServerIds: const ['fetch'],
      catalog: [
        McpServer(
          id: 'fetch',
          name: 'fetch',
          server: const {'type': 'stdio', 'command': 'npx'},
          createdAt: 1,
          updatedAt: 1,
        ),
      ],
      layout: layout,
    );

    await McpRegistryService(layout: layout).writeForSession(
      teamId: teamId,
      sessionId: sessionId,
    );

    final meta =
        jsonDecode(await metaFile.readAsString()) as Map<String, Object?>;
    final servers = (meta['mcpServers'] as Map).cast<String, Object?>();
    expect(servers['fetch'], isNotNull);
    expect(servers['plugin-srv'], isNotNull);
    expect((meta['projects'] as Map)['/repo'], isNotNull);
  });

  test('mcp merge preserves hasCompletedOnboarding when defaults ran first', () async {
    const teamId = 'team-a';
    const sessionId = 'sess-2';
    final memberDir = layout.memberToolDir(teamId, sessionId, 'claude');
    await Directory(memberDir).create(recursive: true);

    final metaFile = File('$memberDir/.claude.json');
    await metaFile.writeAsString(
      jsonEncode({'hasCompletedOnboarding': true}),
    );

    await TeamMcpLinkerService().syncForTeam(
      teamId: teamId,
      mcpServerIds: const ['fetch'],
      catalog: [
        McpServer(
          id: 'fetch',
          name: 'fetch',
          server: const {'type': 'stdio', 'command': 'npx'},
          createdAt: 1,
          updatedAt: 1,
        ),
      ],
      layout: layout,
    );

    await McpRegistryService(layout: layout).writeForSession(
      teamId: teamId,
      sessionId: sessionId,
    );

    final meta =
        jsonDecode(await metaFile.readAsString()) as Map<String, Object?>;
    expect(meta['hasCompletedOnboarding'], isTrue);
    expect((meta['mcpServers'] as Map)['fetch'], isNotNull);
  });
}
