import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/identity_cubit.dart';
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/identity_repository.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/mcp/identity_mcp_linker_service.dart';
import 'package:teampilot/services/plugin/identity_plugin_linker_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';

const _userServer = McpServer(
  id: 'user-mcp',
  name: 'user',
  server: {'command': 'echo'},
);
const _extServer = McpServer(
  id: 'ext:codegraph',
  name: 'codegraph',
  server: {'command': 'codegraph', 'args': ['serve', '--mcp']},
);

/// Records every `syncForIdentity` call and returns queued results in order.
class _RecordingMcpLinker extends IdentityMcpLinkerService {
  _RecordingMcpLinker({this.resultsQueue = const []});

  final List<IdentityMcpSyncResult> resultsQueue;
  final calls =
      <({String identityId, List<String> mcpServerIds, List<McpServer> catalog})>[];
  int _index = 0;

  @override
  Future<IdentityMcpSyncResult> syncForIdentity({
    required String identityId,
    required List<String> mcpServerIds,
    required List<McpServer> catalog,
    required RuntimeLayout layout,
  }) async {
    calls.add((
      identityId: identityId,
      mcpServerIds: List.of(mcpServerIds),
      catalog: List.of(catalog),
    ));
    final result = _index < resultsQueue.length
        ? resultsQueue[_index]
        : const IdentityMcpSyncResult();
    _index++;
    return result;
  }
}

/// No-op plugin linker so `selectTeam` doesn't touch the real catalogs
/// (keeps test output free of benign linker errors).
class _NoopPluginLinker extends IdentityPluginLinkerService {
  _NoopPluginLinker() : super(appPluginsRoot: '/tmp');

  @override
  Future<IdentityPluginSyncResult> syncForIdentity({
    required String identityId,
    required List<String> pluginIds,
    required List<Plugin> installed,
  }) async =>
      const IdentityPluginSyncResult();
}

IdentityRepository _repo(Directory dir) =>
    IdentityRepository(rootDir: p.join(dir.path, 'identities'));

void main() {
  group('mergeExtensionMcp', () {
    const userServer = McpServer(
      id: 'user-mcp',
      name: 'user',
      server: {'command': 'echo'},
    );
    const extServer = McpServer(
      id: 'ext:codegraph',
      name: 'codegraph',
      server: {'command': 'codegraph', 'args': ['serve', '--mcp']},
    );

    test('appends contribution id and server to catalog and ids', () {
      final (catalog, ids) = mergeExtensionMcp(
        catalog: [userServer],
        ids: ['user-mcp'],
        contributions: [extServer],
      );

      expect(ids, ['user-mcp', 'ext:codegraph']);
      expect(catalog.map((s) => s.id), ['user-mcp', 'ext:codegraph']);
    });

    test('does not duplicate an existing id in catalog', () {
      final (catalog, ids) = mergeExtensionMcp(
        catalog: [userServer, extServer],
        ids: ['user-mcp', 'ext:codegraph'],
        contributions: [extServer],
      );

      expect(ids, ['user-mcp', 'ext:codegraph']);
      expect(catalog, hasLength(2));
    });

    test('adds id when contribution server already in catalog', () {
      final (catalog, ids) = mergeExtensionMcp(
        catalog: [extServer],
        ids: const [],
        contributions: [extServer],
      );

      expect(ids, ['ext:codegraph']);
      expect(catalog, hasLength(1));
    });
  });

  group('_syncMcpForSelected wiring (selectTeam)', () {
    late Directory appDataRoot;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      appDataRoot =
          await Directory.systemTemp.createTemp('teampilot_ext_mcp_');
      final paths = AppPaths(appDataRoot.path);
      RuntimeStorageContext.installForTesting(
        filesystem: LocalFilesystem(
          pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
        ),
        paths: paths,
        home: appDataRoot.path,
        cwd: appDataRoot.path,
      );
    });

    tearDown(() async {
      RuntimeStorageContext.resetForTesting();
      AppPathsBootstrapper.resetForTesting();
      if (await appDataRoot.exists()) {
        try {
          await appDataRoot.delete(recursive: true);
        } on FileSystemException catch (_) {
          // Directory may still be in use on some platforms (macOS).
          // The OS will clean up the temp dir eventually.
        }
      }
    });

    test('extension contribution lands in the team MCP snapshot', () async {
      final dir = await Directory.systemTemp.createTemp('team-ext-mcp-');
      final repo = _repo(dir);
      final linker = _RecordingMcpLinker();
      final cubit = IdentityCubit(
        repository: repo,
        sessionRepository: SessionRepository(),
        reloadProjects: () async {},
        executableResolver: () => 'flashskyai',
        mcpLinker: linker,
        pluginLinker: _NoopPluginLinker(),
        installedMcpLoader: () async => [_userServer],
        installedPluginsLoader: () async => [],
        extensionMcpContributor: (teamId) async => [_extServer],
      );

      const team = TeamIdentity(
        id: 't',
        name: 'T',
        members: [TeamMemberConfig(id: 'm', name: 'm')],
        mcpServerIds: ['user-mcp'],
      );
      await repo.saveTeams([team]);
      await cubit.load();

      linker.calls.clear();
      await cubit.selectTeam('t');

      expect(linker.calls, isNotEmpty);
      final call = linker.calls.first;
      expect(call.mcpServerIds, containsAll(['user-mcp', 'ext:codegraph']));
      expect(call.catalog.map((s) => s.id), contains('ext:codegraph'));

      await cubit.close();
      await dir.delete(recursive: true);
    });

    test('prune-branch re-sync still includes the extension contribution',
        () async {
      final dir = await Directory.systemTemp.createTemp('team-ext-mcp-');
      final repo = _repo(dir);
      // First sync reports a missing user id → cubit prunes and re-syncs.
      final linker = _RecordingMcpLinker(
        resultsQueue: const [
          IdentityMcpSyncResult(skippedMissingIds: ['ghost']),
        ],
      );
      final cubit = IdentityCubit(
        repository: repo,
        sessionRepository: SessionRepository(),
        reloadProjects: () async {},
        executableResolver: () => 'flashskyai',
        mcpLinker: linker,
        pluginLinker: _NoopPluginLinker(),
        installedMcpLoader: () async => [_userServer],
        installedPluginsLoader: () async => [],
        extensionMcpContributor: (teamId) async => [_extServer],
      );

      const team = TeamIdentity(
        id: 't',
        name: 'T',
        members: [TeamMemberConfig(id: 'm', name: 'm')],
        mcpServerIds: ['user-mcp', 'ghost'],
      );
      await repo.saveTeams([team]);
      await cubit.load();

      linker.calls.clear();
      await cubit.selectTeam('t');

      // Two calls: initial (skips 'ghost') then the pruned re-sync.
      expect(linker.calls, hasLength(2));
      final reSync = linker.calls[1];
      expect(reSync.mcpServerIds, contains('ext:codegraph'));
      expect(reSync.mcpServerIds, isNot(contains('ghost')));
      expect(reSync.mcpServerIds, contains('user-mcp'));
      expect(reSync.catalog.map((s) => s.id), contains('ext:codegraph'));

      await cubit.close();
      await dir.delete(recursive: true);
    });
  });
}
