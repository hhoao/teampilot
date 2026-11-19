import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/plane_ssh_profile_repository.dart';
import 'package:teampilot/repositories/connection_store.dart';
import 'package:teampilot/repositories/catalog_store.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_resolver.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_targets.dart';
import 'package:teampilot/services/storage/home_storage.dart';

import '../../../support/connection_fixtures.dart';
import '../../../support/in_memory_filesystem.dart';
import '../../../support/post_frame_test_harness.dart';
import '../../../support/test_runtime_context.dart';

Future<void> _writeJson(
  Filesystem fs,
  String path,
  List<Map<String, Object?>> rows,
) async {
  await fs.ensureDir(fs.pathContext.dirname(path));
  await fs.atomicWrite(path, jsonEncode(rows));
}

Map<String, Object?> _row({
  required String id,
  required String name,
  String? vaultEntryId,
}) => {
  'schemaVersion': 1,
  'id': id,
  'name': name,
  'host': 'h',
  'port': 22,
  'username': 'u',
  'authType': 'password',
  if (vaultEntryId != null) 'vaultEntryId': vaultEntryId,
  'updatedAt': 10,
};

void main() {
  group('B-source profileOf through the SSH MCP chain', () {
    late Directory planeDir;
    late HomeStorage planeStorage;

    setUp(() {
      setUpTestAppStorage();
      planeDir = Directory.systemTemp.createTempSync('test_plane_');
      planeStorage = HomeStorage(testRuntimeContext(planeDir.path));
    });

    tearDown(() {
      tearDownTestAppStorage();
      if (planeDir.existsSync()) planeDir.deleteSync(recursive: true);
    });

    PlaneSshProfileRepository buildPlaneRepo() => PlaneSshProfileRepository(
      storage: planeStorage,
      catalog: CatalogStore(storage: planeStorage),
      connections: ConnectionStore(
        rootDir: testHomeStorage.appDataRoot,
        fs: testHomeStorage.fs,
      ),
    );

    Future<void> seedCatalogs() async {
      final deviceStore = ConnectionStore(
        rootDir: testHomeStorage.appDataRoot,
        fs: testHomeStorage.fs,
      );
      await deviceStore.save(
        deviceConnection(machineId: 'plane-1', credentialRef: 'vault-1'),
      );
      await deviceStore.save(
        deviceConnection(machineId: 'device-only', displayName: 'device only'),
      );
      final planeFs = planeStorage.fs;
      await _writeJson(
        planeFs,
        planeFs.pathContext.join(
          planeStorage.paths.sshProfilesDir,
          'profiles.json',
        ),
        [_row(id: 'plane-1', name: 'shared')],
      );
    }

    test(
      'profileOf resolves only plane entries; A-only id returns null',
      () async {
        await seedCatalogs();
        final planeProfiles = await buildPlaneRepo().loadAll();
        final profileOf = _resolverOf(planeProfiles);

        // The plane row is present and borrowed the device's vault reference,
        // which is required for the subsequent connect.
        final resolved = profileOf('plane-1');
        expect(resolved, isNotNull);
        expect(resolved!.id, 'plane-1');
        expect(resolved.vaultEntryId, 'vault-1');
        // The device-local (A source) entry is not part of the B catalog.
        expect(profileOf('device-only'), isNull);
      },
    );

    test(
      'sessionSshMcpTargetsFromFolders keeps only B-source folders',
      () async {
        await seedCatalogs();
        final planeProfiles = await buildPlaneRepo().loadAll();
        final profileOf = _resolverOf(planeProfiles);

        final targets = sessionSshMcpTargetsFromFolders(
          folders: const [
            WorkspaceFolder(path: '/plane', targetId: 'ssh:plane-1'),
            WorkspaceFolder(path: '/device', targetId: 'ssh:device-only'),
          ],
          profileOf: profileOf,
        );

        expect(targets.map((t) => t.profile.id), ['plane-1']);
        expect(targets.single.folderPaths, ['/plane']);
      },
    );

    test(
      'resolveSessionSshMcpContext produces only B-source targets',
      () async {
        await seedCatalogs();
        final planeProfiles = await buildPlaneRepo().loadAll();
        final profileOf = _resolverOf(planeProfiles);
        final session = AppSession(
          sessionId: 'sess-1',
          workspaceId: 'ws',
          createdAt: 1,
        );
        final workspace = Workspace(
          workspaceId: 'ws',
          createdAt: 1,
          folders: const [
            WorkspaceFolder(path: '/plane', targetId: 'ssh:plane-1'),
            WorkspaceFolder(path: '/device', targetId: 'ssh:device-only'),
          ],
          injectSessionSshMcp: true,
        );

        final context = resolveSessionSshMcpContext(
          session: session,
          workspace: workspace,
          profileOf: profileOf,
          localFs: InMemoryFilesystem(),
          localUsesPosixPaths: true,
        );

        expect(context.targets.map((t) => t.profile.id), ['plane-1']);
      },
    );

    test(
      'empty plane catalog resolves no targets (no error, no A fallback)',
      () async {
        // Device A source has an entry; the plane B source has none.
        await ConnectionStore(
          rootDir: testHomeStorage.appDataRoot,
          fs: testHomeStorage.fs,
        ).save(deviceConnection(machineId: 'device-only'));
        final planeProfiles = await buildPlaneRepo().loadAll();
        final profileOf = _resolverOf(planeProfiles);

        expect(planeProfiles, isEmpty);
        expect(profileOf('device-only'), isNull);
        final targets = sessionSshMcpTargetsFromFolders(
          folders: const [
            WorkspaceFolder(path: '/device', targetId: 'ssh:device-only'),
          ],
          profileOf: profileOf,
        );
        expect(targets, isEmpty);
      },
    );
  });
}

SshProfile? Function(String id) _resolverOf(List<SshProfile> profiles) =>
    (id) {
      for (final profile in profiles) {
        if (profile.id == id) return profile;
      }
      return null;
    };
