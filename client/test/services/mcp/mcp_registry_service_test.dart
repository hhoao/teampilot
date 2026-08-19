import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/mcp/mcp_registry_service.dart';
import 'package:teampilot/services/mcp/mcp_registry_config_service.dart';
import 'package:teampilot/models/mcp_registry_source.dart';
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/models/mcp_server_spec.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/mcp/profile_mcp_linker_service.dart';
import 'package:teampilot/services/cli/registry/capabilities/mcp_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/cli/claude/capabilities/provider.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late RuntimeLayout layout;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mcp_registry_');
    layout = RuntimeLayout(teampilotRoot: root.path);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'merges catalog into claude metadata preserving other servers',
    () async {
      const teamId = 'team-a';
      const sessionId = 'sess-1';
      final memberDir = layout.sessionRuntimeToolDir(
        'workspace-1',
        sessionId,
        'claude',
      );
      await Directory(memberDir).create(recursive: true);

      final metaFile = File('$memberDir/.claude.json');
      await metaFile.writeAsString(
        jsonEncode({
          'hasCompletedOnboarding': true,
          'mcpServers': {
            'plugin-srv': {'type': 'stdio', 'command': 'plugin'},
          },
          'workspaces': {
            '/repo': {'hasTrustDialogAccepted': true},
          },
        }),
      );

      await ProfileMcpLinkerService().syncForProfile(
        profileId: teamId,
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
        workspaceId: 'workspace-1',
        teamId: teamId,
        sessionId: sessionId,
      );

      final meta =
          jsonDecode(await metaFile.readAsString()) as Map<String, Object?>;
      final servers = (meta['mcpServers'] as Map).cast<String, Object?>();
      expect(servers['fetch'], isNotNull);
      expect(servers['plugin-srv'], isNotNull);
      expect((meta['workspaces'] as Map)['/repo'], isNotNull);
    },
  );

  test(
    'mcp merge preserves hasCompletedOnboarding when defaults ran first',
    () async {
      const teamId = 'team-a';
      const sessionId = 'sess-2';
      final memberDir = layout.sessionRuntimeToolDir(
        'workspace-1',
        sessionId,
        'claude',
      );
      await Directory(memberDir).create(recursive: true);

      final metaFile = File('$memberDir/.claude.json');
      await metaFile.writeAsString(
        jsonEncode({'hasCompletedOnboarding': true}),
      );

      await ProfileMcpLinkerService().syncForProfile(
        profileId: teamId,
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
        workspaceId: 'workspace-1',
        teamId: teamId,
        sessionId: sessionId,
      );

      final meta =
          jsonDecode(await metaFile.readAsString()) as Map<String, Object?>;
      expect(meta['hasCompletedOnboarding'], isTrue);
      expect((meta['mcpServers'] as Map)['fetch'], isNotNull);
    },
  );

  test('session merge injects Smithery Bearer only for gateway URLs', () async {
    const teamId = 'team-a';
    const sessionId = 'sess-auth';
    final memberDir = layout.sessionRuntimeToolDir(
      'workspace-1',
      sessionId,
      'claude',
    );
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

    await ProfileMcpLinkerService().syncForProfile(
      profileId: teamId,
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
      workspaceId: 'workspace-1',
      teamId: teamId,
      sessionId: sessionId,
    );

    final meta =
        jsonDecode(await File('$memberDir/.claude.json').readAsString())
            as Map<String, Object?>;
    final servers = meta['mcpServers'] as Map;
    expect((servers['ctx-gw'] as Map)['headers'], isNotNull);
    expect(
      (servers['ctx-gw'] as Map)['headers']['Authorization'],
      'Bearer registry-secret',
    );
    expect((servers['Context7'] as Map).containsKey('headers'), isFalse);
  });

  test(
    'extraServers merge into claude metadata without team catalog',
    () async {
      const teamId = 'team-a';
      const sessionId = 'sess-bus';
      final memberDir = layout.sessionRuntimeToolDir(
        'workspace-1',
        sessionId,
        'claude',
      );
      await Directory(memberDir).create(recursive: true);

      final metaFile = File(
        p.join(memberDir, ClaudeProviderCapability.metadataFileName),
      );
      await metaFile.writeAsString(
        jsonEncode({'hasCompletedOnboarding': true}),
      );

      const endpoint = 'http://127.0.0.1:4242/mcp';
      await McpRegistryService(layout: layout).writeForSession(
        workspaceId: 'workspace-1',
        teamId: teamId,
        sessionId: sessionId,
        extraServers: {
          teammateBusMcpServerName: teammateBusMcpServerConfig(
            endpoint: Uri.parse(endpoint),
            memberId: 'worker-1',
            sessionId: sessionId,
          ),
        },
      );

      final meta =
          jsonDecode(await metaFile.readAsString()) as Map<String, Object?>;
      final servers = (meta['mcpServers'] as Map).cast<String, Object?>();
      final bus = (servers[teammateBusMcpServerName] as Map)
          .cast<String, Object?>();
      expect(bus['type'], 'http');
      expect(bus['url'], endpoint);
      expect((bus['headers'] as Map)['X-Member'], 'worker-1');
      expect((bus['headers'] as Map)['X-Session'], sessionId);
    },
  );

  test(
    'empty simple MCP input is a no-op without loading catalog settings',
    () async {
      await McpRegistryService(
        layout: layout,
        registryConfigService: _FailingMcpRegistryConfigService(),
      ).writeForSimpleSession(
        workspaceId: 'workspace-empty',
        sessionId: 'session-empty',
        mcpServerIds: const [],
      );
    },
  );

  test('plugin-only MCP input skips catalog and Smithery providers', () async {
    await McpRegistryService(
      layout: layout,
      registryConfigService: _FailingMcpRegistryConfigService(),
    ).writeForSimpleSession(
      workspaceId: 'workspace-plugin',
      sessionId: 'session-plugin',
      mcpServerIds: const [],
      pluginIds: const ['missing-plugin'],
    );
  });

  test(
    'cursor warm assembly is reused and empty snapshot skips credential merge',
    () async {
      const teamId = 'team-empty-snapshot';
      await Directory(layout.identityMcpDir(teamId)).create(recursive: true);
      await File(
        layout.identityMcpServersFile(teamId),
      ).writeAsString(jsonEncode({'mcpServers': <String, Object?>{}}));

      final writer = _RecordingMcpCapability();
      final config = _CountingMcpRegistryConfigService();
      final service = McpRegistryService(
        layout: layout,
        registryConfigService: config,
        cliRegistry: CliToolRegistry()..register(_CursorTestTool(writer)),
      );

      final assembly = await service.writeCursorWorkspaceMcpBase(
        workspaceId: 'workspace-empty-snapshot',
        teamId: teamId,
        extraServers: const {
          'extra': {'type': 'stdio', 'command': 'extra-command'},
        },
        pluginIds: const ['missing-plugin'],
      );
      await service.mergeCursorMemberMcpCredentials(
        workspaceId: 'workspace-empty-snapshot',
        sessionId: 'session-empty-snapshot',
        teamId: teamId,
        memberId: 'member-empty-snapshot',
        assembly: assembly,
      );

      expect(assembly.hasValidCatalogContribution, isFalse);
      expect(writer.writeCalls, 1);
      expect(writer.mergeCalls, 0);
      expect(config.loadCalls, 1);
    },
  );

  test(
    'empty specs still clean invalid TeamBus extra from project scope',
    () async {
      final projectRoot = Directory('${root.path}/project');
      await projectRoot.create(recursive: true);
      final projectMcp = File('${projectRoot.path}/.mcp.json');
      await projectMcp.writeAsString(
        jsonEncode({
          'mcpServers': {
            teammateBusMcpServerName: {'type': 'stdio', 'command': 'stale'},
          },
        }),
      );

      await McpRegistryService(layout: layout).writeForSimpleSession(
        workspaceId: 'workspace-stale',
        sessionId: 'session-stale',
        mcpServerIds: const [],
        extraServers: const {
          teammateBusMcpServerName: {'invalid': true},
        },
        projectMcpRoots: [projectRoot.path],
      );

      expect(await projectMcp.exists(), isFalse);
    },
  );
}

final class _FailingMcpRegistryConfigService extends McpRegistryConfigService {
  _FailingMcpRegistryConfigService() : super();

  @override
  Future<McpRegistrySourcesConfig> load() async {
    throw StateError('catalog settings must not be loaded');
  }
}

final class _CountingMcpRegistryConfigService extends McpRegistryConfigService {
  int loadCalls = 0;

  @override
  Future<McpRegistrySourcesConfig> load() async {
    loadCalls++;
    return McpRegistrySourcesConfig.defaults();
  }
}

final class _CursorTestTool implements CliToolDefinition {
  const _CursorTestTool(this.writer);

  final McpCapability writer;

  @override
  CliTool get id => CliTool.cursor;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => [writer];
}

final class _RecordingMcpCapability implements McpCapability {
  int writeCalls = 0;
  int mergeCalls = 0;

  @override
  Future<void> write({
    required Filesystem fs,
    required String configDir,
    required List<McpServerSpec> servers,
    String? outputBasename,
  }) async {
    writeCalls++;
  }

  @override
  Future<void> mergeAppCredentials({
    required Filesystem fs,
    required String appConfigDir,
    required String sessionConfigDir,
    String? fallbackAppConfigDir,
  }) async {
    mergeCalls++;
  }
}
