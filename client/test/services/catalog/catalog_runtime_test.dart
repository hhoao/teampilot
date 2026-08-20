import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/team/launch_profile_cubit_host.dart';
import 'package:teampilot/cubits/team/model/launch_profile_state.dart';
import 'package:teampilot/cubits/team/team_profile_provisioner.dart';
import 'package:teampilot/cubits/team/team_resource_sync_service.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/mcp_repository.dart';
import 'package:teampilot/repositories/plugin_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/catalog/catalog_mcp_handler.dart';
import 'package:teampilot/services/catalog/catalog_runtime.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/mcp/profile_mcp_linker_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/team_bus/mcp/jsonrpc.dart';

void main() {
  late Directory tmp;
  late Directory workRoot;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('catalog_runtime_');
    workRoot = Directory.systemTemp.createTempSync('catalog_runtime_work_');
    final paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
  });

  tearDown(() {
    AppStorage.resetForTesting();
    AppPathsBootstrapper.resetForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    if (workRoot.existsSync()) workRoot.deleteSync(recursive: true);
  });

  CatalogMcpSession mcpSession() => CatalogMcpSession(
    sessionId: 's1',
    workspaceId: 'ws1',
    workFs: LocalFilesystem(),
    allowedRoots: [workRoot.path],
  );

  Future<Map<String, Object?>> callTool({
    required CatalogRuntime runtime,
    required String name,
    required Map<String, Object?> arguments,
    required CatalogMcpSession session,
  }) async {
    final res = await runtime.handler.handle(
      JsonRpcRequest(
        id: 1,
        method: 'tools/call',
        params: {'name': name, 'arguments': arguments},
      ),
      session,
    );
    expect(res, isNotNull);
    expect(res!.result!['isError'], isFalse);
    final text = (res.result!['content'] as List).first['text'] as String;
    return jsonDecode(text) as Map<String, Object?>;
  }

  test(
    'assemble round-trips create_skill then list_installed without widgets',
    () async {
      final runtime = CatalogRuntime.assemble();
      final session = mcpSession();

      final created = await callTool(
        runtime: runtime,
        name: 'create_skill',
        arguments: {
          'name': 'Hello Skill',
          'directory': 'hello-skill',
          'body': 'Do the thing.',
        },
        session: session,
      );
      expect(created['ok'], isTrue);
      expect(created['ids'], ['local:hello-skill']);
      expect(created['restart_required'], isTrue);
      expect(created['message'], contains('Reconnect'));

      final listed = await callTool(
        runtime: runtime,
        name: 'list_installed',
        arguments: {'kind': 'skill'},
        session: session,
      );
      expect(listed['ok'], isTrue);
      final skill = listed['data'] is Map
          ? (listed['data'] as Map)['skill'] as Map<Object?, Object?>?
          : null;
      expect(skill?['boundIds'], contains('local:hello-skill'));
    },
  );

  test(
    'resolveSession uses findById and session folder paths as allowedRoots',
    () async {
      final sessions = SessionRepository();
      final workspace = await sessions.createWorkspace([
        WorkspaceFolder(path: workRoot.path),
      ]);
      final created = (await sessions.createSession(
        workspace.workspaceId,
      )).session;
      final runtime = CatalogRuntime.assemble(sessions: sessions);

      final resolved = await runtime.resolveSession(created.sessionId);
      expect(resolved, isNotNull);
      expect(resolved!.sessionId, created.sessionId);
      expect(resolved.workspaceId, workspace.workspaceId);
      expect(resolved.allowedRoots, created.folderPaths);
      expect(identical(resolved.workFs, AppStorage.fs), isTrue);

      expect(await runtime.resolveSession('missing-session'), isNull);
    },
  );

  test(
    'assemble with a search lambda returns those hits from search_skills',
    () async {
      final runtime = CatalogRuntime.assemble(
        searchSkills: (query) async => [
          {'id': 'acme/foo', 'name': 'Foo', 'query': query},
        ],
      );
      final result = await callTool(
        runtime: runtime,
        name: 'search_skills',
        arguments: {'query': 'foo'},
        session: mcpSession(),
      );
      expect(result['ok'], isTrue);
      expect(result['data'], {
        'results': [
          {'id': 'acme/foo', 'name': 'Foo', 'query': 'foo'},
        ],
      });
    },
  );

  test(
    'create_skill with bind_to team does not write skills/installed',
    () async {
      final runtime = CatalogRuntime.assemble();
      final res = await runtime.handler.handle(
        const JsonRpcRequest(
          id: 2,
          method: 'tools/call',
          params: {
            'name': 'create_skill',
            'arguments': {
              'name': 'Team Only',
              'directory': 'team-only',
              'body': 'nope',
              'bind_to': 'team',
            },
          },
        ),
        mcpSession(),
      );
      expect(res, isNotNull);
      expect(res!.result!['isError'], isTrue);
      final text = (res.result!['content'] as List).first['text'] as String;
      expect(text, contains('code=bind_scope_unsupported'));
      expect(
        File(
          p.join(tmp.path, 'skills/installed/team-only/SKILL.md'),
        ).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'create_skill conflict without overwrite is a toolError not a throw',
    () async {
      final runtime = CatalogRuntime.assemble();
      final session = mcpSession();
      await callTool(
        runtime: runtime,
        name: 'create_skill',
        arguments: {
          'name': 'Hello Skill',
          'directory': 'hello-skill',
          'body': 'Do the thing.',
        },
        session: session,
      );

      final res = await runtime.handler.handle(
        const JsonRpcRequest(
          id: 3,
          method: 'tools/call',
          params: {
            'name': 'create_skill',
            'arguments': {
              'name': 'Hello Skill',
              'directory': 'hello-skill',
              'body': 'again',
            },
          },
        ),
        session,
      );
      expect(res, isNotNull);
      expect(res!.result!['isError'], isTrue);
      final text = (res.result!['content'] as List).first['text'] as String;
      expect(text, contains(RegExp(r'code=(already_exists|install_failed)')));
    },
  );

  test('delete_skill drops the id from all team configs', () async {
    const team = TeamProfile(
      id: 't',
      name: 'T',
      skillIds: ['local:hello-skill'],
    );
    final host = _RecordingHost(
      const LaunchProfileState(
        identities: [team],
        selectedTeamId: 't',
        isLoading: false,
      ),
    );
    final sync = TeamResourceSyncService(
      host: host,
      provisioner: TeamProfileProvisioner(),
      mcpLinker: ProfileMcpLinkerService(),
      pluginRepository: PluginRepository(),
      mcpRepository: McpRepository(),
      extensionMcpContributor: (_) async => const [],
    );
    final runtime = CatalogRuntime.assemble(
      removeSkillFromAllTeams: sync.removeSkillFromAllTeams,
    );
    final session = mcpSession();
    await callTool(
      runtime: runtime,
      name: 'create_skill',
      arguments: {
        'name': 'Hello Skill',
        'directory': 'hello-skill',
        'body': 'Do the thing.',
      },
      session: session,
    );

    await callTool(
      runtime: runtime,
      name: 'delete_skill',
      arguments: {'id': 'local:hello-skill'},
      session: session,
    );

    expect(host.state.teams.single.skillIds, isEmpty);
  });

  test('delete_plugin drops the id from all team configs', () async {
    const pluginId = 'local/demo';
    const team = TeamProfile(id: 't', name: 'T', pluginIds: [pluginId]);
    final host = _RecordingHost(
      const LaunchProfileState(
        identities: [team],
        selectedTeamId: 't',
        isLoading: false,
      ),
    );
    final sync = TeamResourceSyncService(
      host: host,
      provisioner: TeamProfileProvisioner(),
      mcpLinker: ProfileMcpLinkerService(),
      pluginRepository: PluginRepository(),
      mcpRepository: McpRepository(),
      extensionMcpContributor: (_) async => const [],
    );
    final runtime = CatalogRuntime.assemble(
      removePluginFromAllTeams: sync.removePluginFromAllTeams,
    );
    final pluginSrc = Directory(p.join(workRoot.path, 'demo'))..createSync();
    File(
      p.join(pluginSrc.path, 'plugin.json'),
    ).writeAsStringSync('{ "name": "demo" }');
    await callTool(
      runtime: runtime,
      name: 'import_plugin',
      arguments: {'path': pluginSrc.path},
      session: mcpSession(),
    );

    await callTool(
      runtime: runtime,
      name: 'delete_plugin',
      arguments: {'id': pluginId},
      session: mcpSession(),
    );

    expect(host.state.teams.single.pluginIds, isEmpty);
  });

  test('delete_mcp drops the id from all team configs', () async {
    const team = TeamProfile(id: 't', name: 'T', mcpServerIds: ['echo']);
    final host = _RecordingHost(
      const LaunchProfileState(
        identities: [team],
        selectedTeamId: 't',
        isLoading: false,
      ),
    );
    final sync = TeamResourceSyncService(
      host: host,
      provisioner: TeamProfileProvisioner(),
      mcpLinker: ProfileMcpLinkerService(),
      pluginRepository: PluginRepository(),
      mcpRepository: McpRepository(),
      extensionMcpContributor: (_) async => const [],
    );
    final runtime = CatalogRuntime.assemble(
      removeMcpFromAllTeams: sync.removeMcpFromAllTeams,
    );
    await callTool(
      runtime: runtime,
      name: 'create_mcp',
      arguments: {'name': 'echo', 'command': 'npx'},
      session: mcpSession(),
    );

    await callTool(
      runtime: runtime,
      name: 'delete_mcp',
      arguments: {'id': 'echo'},
      session: mcpSession(),
    );

    expect(host.state.teams.single.mcpServerIds, isEmpty);
  });
}

final class _RecordingHost implements LaunchProfileCubitHost {
  _RecordingHost(this.state);

  @override
  LaunchProfileState state;

  @override
  bool get isClosed => false;

  @override
  void applyState(LaunchProfileState next) => state = next;

  @override
  Future<void> saveTeamProfiles(List<TeamProfile> teams) async {}
}
