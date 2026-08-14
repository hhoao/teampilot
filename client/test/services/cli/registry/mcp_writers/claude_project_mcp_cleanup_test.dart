import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/mcp_project_cleanup.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/mcp/mcp_registry_service.dart';
import 'package:teampilot/services/cli/claude/capabilities/provider.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:path/path.dart' as p;

import '../../../../support/in_memory_filesystem.dart';

void main() {
  group('removeClaudeProjectMcpServers', () {
    test('removes named servers and deletes empty project mcp file', () async {
      final fs = InMemoryFilesystem();
      const projectRoot = '/repo';
      await fs.writeString(
        '$projectRoot/.mcp.json',
        jsonEncode({
          'mcpServers': {
            teammateBusMcpServerName: {
              'command': 'sh',
              'args': ['-c', 'nc 127.0.0.1 1'],
            },
            'fetch': {'type': 'stdio', 'command': 'npx'},
          },
        }),
      );

      await removeClaudeProjectMcpServers(
        fs: fs,
        projectRoots: const [projectRoot],
        serverNames: const [teammateBusMcpServerName],
      );

      final raw = await fs.readString('$projectRoot/.mcp.json');
      final decoded = jsonDecode(raw!) as Map<String, Object?>;
      final servers = (decoded['mcpServers'] as Map).cast<String, Object?>();
      expect(servers.containsKey(teammateBusMcpServerName), isFalse);
      expect(servers.containsKey('fetch'), isTrue);
    });

    test('no-op when project mcp file is missing', () async {
      final fs = InMemoryFilesystem();
      await removeClaudeProjectMcpServers(
        fs: fs,
        projectRoots: const ['/missing'],
        serverNames: const [teammateBusMcpServerName],
      );
    });
  });

  group('McpRegistryService project cleanup', () {
    late Directory root;
    late RuntimeLayout layout;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('mcp_registry_cleanup_');
      layout = RuntimeLayout(teampilotRoot: root.path);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test(
      'writeForSession removes stale teammate-bus from project .mcp.json',
      () async {
        const teamId = 'team-a';
        const sessionId = 'sess-bus';
        final projectRoot = p.join(root.path, 'hhoa');
        final memberDir = layout.sessionRuntimeToolDir(
          'workspace-1',
          sessionId,
          'claude',
        );
        await Directory(memberDir).create(recursive: true);
        await Directory(projectRoot).create(recursive: true);

        await File(
          p.join(memberDir, ClaudeProviderCapability.metadataFileName),
        ).writeAsString(jsonEncode({'hasCompletedOnboarding': true}));

        await File(p.join(projectRoot, '.mcp.json')).writeAsString(
          jsonEncode({
            'mcpServers': {
              teammateBusMcpServerName: {
                'command': 'sh',
                'args': ['-c', 'nc 127.0.0.1 46669'],
              },
            },
          }),
        );

        await McpRegistryService(layout: layout).writeForSession(
          workspaceId: 'workspace-1',
          teamId: teamId,
          sessionId: sessionId,
          projectMcpRoots: [projectRoot],
          extraServers: {
            teammateBusMcpServerName: teammateBusMcpServerConfig(
              endpoint: Uri.parse('http://127.0.0.1:4242/mcp'),
              memberId: 'builder',
              sessionId: sessionId,
            ),
          },
        );

        expect(await File(p.join(projectRoot, '.mcp.json')).exists(), isFalse);
      },
    );
  });
}
