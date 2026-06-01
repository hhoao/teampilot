import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/mcp/mcp_registry_service.dart';
import 'package:teampilot/models/mcp_registry_source.dart';
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/services/mcp/team_mcp_linker_service.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:path/path.dart' as p;

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

  test('session merge injects Smithery Bearer only for gateway URLs', () async {
    const teamId = 'team-a';
    const sessionId = 'sess-auth';
    final memberDir = layout.memberToolDir(teamId, sessionId, 'claude');
    await Directory(memberDir).create(recursive: true);

    await Directory(p.join(root.path, 'mcp')).create(recursive: true);
    await File(p.join(root.path, 'mcp', 'registry_sources.json')).writeAsString(
      jsonEncode(
        McpRegistrySourcesConfig(
          sources: [
            McpRegistrySourceConfig(
              kind: McpRegistrySourceKind.smithery,
              baseUrl: McpRegistrySourceConfig.defaultBaseUrl(
                McpRegistrySourceKind.smithery,
              ),
              apiToken: 'registry-secret',
            ),
          ],
        ).toJson(),
      ),
    );

    await TeamMcpLinkerService().syncForTeam(
      teamId: teamId,
      mcpServerIds: const ['ctx', 'deploy'],
      catalog: [
        McpServer(
          id: 'ctx',
          name: 'ctx-gw',
          server: const {
            'type': 'http',
            'url': 'https://server.smithery.ai/@context7',
          },
          createdAt: 1,
          updatedAt: 1,
        ),
        McpServer(
          id: 'deploy',
          name: 'Context7',
          server: const {
            'type': 'http',
            'url': 'https://context7-mcp--upstash.run.tools',
          },
          smitheryHosted: true,
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

    final meta = jsonDecode(
      await File('$memberDir/.claude.json').readAsString(),
    ) as Map<String, Object?>;
    final servers = meta['mcpServers'] as Map;
    expect(
      (servers['ctx-gw'] as Map)['headers'],
      isNotNull,
    );
    expect(
      (servers['ctx-gw'] as Map)['headers']['Authorization'],
      'Bearer registry-secret',
    );
    expect((servers['Context7'] as Map).containsKey('headers'), isFalse);
  });

  test('extraServers merge into claude metadata without team catalog', () async {
    const teamId = 'team-a';
    const sessionId = 'sess-bus';
    final memberDir = layout.memberToolDir(teamId, sessionId, 'claude');
    await Directory(memberDir).create(recursive: true);

    final metaFile = File(
      p.join(memberDir, ConfigProfileService.claudeMetadataFileName),
    );
    await metaFile.writeAsString(
      jsonEncode({'hasCompletedOnboarding': true}),
    );

    const endpoint = 'http://127.0.0.1:4242/mcp';
    await McpRegistryService(layout: layout).writeForSession(
      teamId: teamId,
      sessionId: sessionId,
      extraServers: {
        teammateBusMcpServerName: teammateBusMcpServerConfig(
          endpoint: Uri.parse(endpoint),
          memberId: 'worker-1',
        ),
      },
    );

    final meta =
        jsonDecode(await metaFile.readAsString()) as Map<String, Object?>;
    final servers = (meta['mcpServers'] as Map).cast<String, Object?>();
    final bus = (servers[teammateBusMcpServerName] as Map).cast<String, Object?>();
    expect(bus['type'], 'http');
    expect(bus['url'], endpoint);
    expect((bus['headers'] as Map)['X-Member'], 'worker-1');
  });
}
